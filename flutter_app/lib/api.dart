/// HTTP client for the MURA Django REST API (docs/api-contract.md v1).
///
/// - Singleton access via [ApiClient.instance]; base URL is supplied through
///   the build-time MURA_API_URL define.
/// - Access/refresh JWTs live in flutter_secure_storage.
/// - Every authorized request attaches 'Authorization: Bearer `<access>`'.
/// - On 401 the client tries ONE refresh + retry; if that also fails it
///   wipes the session, notifies [ApiClient.sessionEpoch] listeners and
///   pushes '/login' through [muraNavigatorKey].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Navigator key owned by the API layer so it can force a logout navigation.
/// MaterialApp in main.dart installs it as its navigatorKey.
final GlobalKey<NavigatorState> muraNavigatorKey = GlobalKey<NavigatorState>();

/// Error surfaced by [ApiClient] for any non-2xx or malformed response.
class ApiException implements Exception {
  ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null
      ? 'ApiException: $message'
      : 'ApiException($status): $message';
}

/// Converts any thrown error into a short, human-readable message.
/// Raw Dart exception text and HTTP codes are never shown to the user —
/// they stay in the console log for diagnosis instead.
String friendlyError(Object error) {
  if (error is ApiException) {
    final String m = error.message.trim();
    return m.isEmpty ? 'Something went wrong. Please try again.' : m;
  }
  if (error is TimeoutException) {
    return 'The server took too long to respond. Please try again.';
  }
  if (error is SocketException) {
    return 'No connection to the server. Check your internet and try again.';
  }
  return 'Something went wrong. Please try again.';
}

/// Shared API client.
class ApiClient {
  static const MethodChannel _motionQuoteChannel =
      MethodChannel('com.bubaa.mura/motion_quote');
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// Override for deployments with:
  /// flutter run --dart-define=MURA_API_URL=https://your-api.example.com/api/v1
  static const String _configuredBaseUrl = String.fromEnvironment(
    'MURA_API_URL',
    defaultValue: 'https://bubaa.pythonanywhere.com/api/v1',
  );

  static String get baseUrl =>
      _configuredBaseUrl.replaceFirst(RegExp(r'/+$'), '');

  /// Base URL for serving media files (images, avatars, photos).
  /// This is separate from the API base URL because media is served
  /// from the root domain, not under /api/v1/.
  ///
  /// Derived at runtime from the resolved [baseUrl] (scheme + host + port,
  /// dropping the /api/v1 path) so a MURA_API_URL override also redirects
  /// media; falls back to the production host when parsing fails.
  static String get mediaBaseUrl {
    try {
      final Uri uri = Uri.parse(baseUrl);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        return uri.replace(path: '', query: null, fragment: null).toString();
      }
    } catch (_) {
      // Fall through to the default host below.
    }
    return 'https://bubaa.pythonanywhere.com';
  }

  /// Builds a full URL for media files (avatars, photos, etc.)
  ///
  /// Example:
  ///   getMediaUrl('/media/avatars/photo.jpg')
  ///   => 'https://bubaa.pythonanywhere.com/media/avatars/photo.jpg'
  ///
  /// Handles:
  ///   - null/empty paths -> returns empty string
  ///   - absolute URLs (http/https) -> returns as-is
  ///   - relative paths -> prepends mediaBaseUrl and ensures leading slash
  String getMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    // If it's already an absolute URL, return as-is.
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    // Ensure the path starts with a slash.
    final String normalized = path.startsWith('/') ? path : '/$path';
    return '$mediaBaseUrl$normalized';
  }

  final http.Client _http = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kAccessKey = 'mura.jwt.access';
  static const String _kRefreshKey = 'mura.jwt.refresh';

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;

  /// Bumped every time tokens are wiped (logout after a failed refresh).
  /// MuraApp listens on this to reset its auth gate state.
  final ValueNotifier<int> sessionEpoch = ValueNotifier<int>(0);

  // -----------------------------------------------------------------------
  // Session plumbing
  // -----------------------------------------------------------------------

  Future<String?> _ensureAccessToken() async {
    _accessToken ??= await _storage.read(key: _kAccessKey);
    _refreshToken ??= await _storage.read(key: _kRefreshKey);
    return _accessToken;
  }

  /// True when a token (access or refresh) exists, i.e. the auth gate should
  /// let the user into the app shell instead of /login.
  Future<bool> hasToken() async {
    await _ensureAccessToken();
    return (_accessToken != null && _accessToken!.isNotEmpty) ||
        (_refreshToken != null && _refreshToken!.isNotEmpty);
  }

  Future<void> _persistTokens(String? access, String? refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    if (access == null || access.isEmpty) {
      await _storage.delete(key: _kAccessKey);
    } else {
      await _storage.write(key: _kAccessKey, value: access);
    }
    if (refresh == null || refresh.isEmpty) {
      await _storage.delete(key: _kRefreshKey);
    } else {
      await _storage.write(key: _kRefreshKey, value: refresh);
    }
  }

  /// Single-flight refresh; true when a fresh access token was stored.
  Future<bool> _refreshAccessToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    _refreshToken ??= await _storage.read(key: _kRefreshKey);
    final String? refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final http.Response response = await _http.post(
        _uri('/auth/token/refresh/'),
        headers: const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, String>{'refresh': refresh}),
      );
      if (response.statusCode != 200) return false;
      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final String? access =
          decoded is Map<String, dynamic> ? decoded['access'] as String? : null;
      if (access == null || access.isEmpty) return false;
      _accessToken = access;
      await _storage.write(key: _kAccessKey, value: access);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clears stored credentials and routes back to the login screen.
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: _kAccessKey);
    await _storage.delete(key: _kRefreshKey);
    sessionEpoch.value++;
    muraNavigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/login',
      (Route<dynamic> route) => false,
    );
  }

  // -----------------------------------------------------------------------
  // Request core
  // -----------------------------------------------------------------------

  Uri _uri(String path, [Map<String, String>? query]) {
    // Absolute URLs (e.g. DRF pagination 'next' links) are fetched as-is.
    final Uri uri = path.startsWith('http://') || path.startsWith('https://')
        ? Uri.parse(path)
        : Uri.parse(baseUrl + path);
    if (query != null && query.isNotEmpty) {
      return uri.replace(
        queryParameters: <String, String>{...uri.queryParameters, ...query},
      );
    }
    return uri;
  }

  Map<String, String> _cleanQuery(Map<String, String?> raw) => <String, String>{
        for (final MapEntry<String, String?> entry in raw.entries)
          if (entry.value != null && entry.value!.isNotEmpty)
            entry.key: entry.value!,
      };

  Future<http.Response> _dispatch(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authorized = true,
  }) async {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    if (authorized) {
      final String? access = await _ensureAccessToken();
      if (access != null && access.isNotEmpty) {
        headers['Authorization'] = 'Bearer $access';
      }
    }
    final Uri uri = _uri(path, query);
    // Request tracing stays in debug builds only; release logs stay clean.
    if (kDebugMode) {
      // ignore: avoid_print
      print('[MURA] -> $method $uri');
    }
    try {
      final http.Response res;
      switch (method) {
        case 'GET':
          res = await _http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
          break;
        case 'POST':
          res = await _http
              .post(uri,
                  headers: headers,
                  body: jsonEncode(body ?? const <String, dynamic>{}))
              .timeout(const Duration(seconds: 20));
          break;
        case 'PATCH':
          res = await _http
              .patch(uri,
                  headers: headers,
                  body: jsonEncode(body ?? const <String, dynamic>{}))
              .timeout(const Duration(seconds: 20));
          break;
        case 'PUT':
          res = await _http
              .put(uri,
                  headers: headers,
                  body: jsonEncode(body ?? const <String, dynamic>{}))
              .timeout(const Duration(seconds: 20));
          break;
        case 'DELETE':
          res = await _http
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
          break;
        default:
          throw ArgumentError.value(
              method, 'method', 'Unsupported HTTP method');
      }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[MURA] <- ${res.statusCode} $method $uri');
    }
    return res;
    } on TimeoutException {
      throw ApiException(
          'The server took too long to respond. Please try again.');
    } on SocketException {
      throw ApiException(
          'Network connection failed. Please check your internet and try again.');
    }
  }

  /// Sends a JSON request; retries ONCE behind a token refresh on 401, and
  /// logs out when the retry is rejected too.
  Future<dynamic> _jsonRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authorized = true,
  }) async {
    http.Response response;
    try {
      response = await _dispatch(method, path,
          body: body, query: query, authorized: authorized);
    } on ApiException {
      if (method != 'GET') rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      response = await _dispatch(method, path,
          body: body, query: query, authorized: authorized);
    }
    if (authorized &&
        response.statusCode == 401 &&
        await _refreshAccessToken()) {
      response = await _dispatch(method, path,
          body: body, query: query, authorized: authorized);
    }
    if (authorized && response.statusCode == 401) {
      await logout();
      throw ApiException('Your session expired. Please sign in again.',
          status: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFrom(response);
    }
    final String text = utf8.decode(response.bodyBytes);
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  ApiException _errorFrom(http.Response response) {
    String message = 'Request failed (${response.statusCode}).';
    try {
      final String text = utf8.decode(response.bodyBytes);
      if (text.isNotEmpty) {
        final dynamic decoded = jsonDecode(text);
        if (decoded is String && decoded.trim().isNotEmpty) {
          message = decoded;
        } else if (decoded is Map<String, dynamic>) {
          final dynamic detail = decoded['detail'];
          if (detail is String && detail.trim().isNotEmpty) {
            message = detail;
          } else {
            final List<String> parts = <String>[];
            decoded.forEach((String key, dynamic value) {
              if (value is List) {
                parts.add('$key: ${value.join(', ')}');
              } else if (value != null) {
                parts.add('$key: $value');
              }
            });
            if (parts.isNotEmpty) message = parts.join('; ');
          }
        }
      }
    } catch (_) {
      // Keep the default message when the body is not decodable JSON.
    }
    return ApiException(message, status: response.statusCode);
  }

  Map<String, dynamic> _asMap(dynamic payload, String path) {
    if (payload is Map<String, dynamic>) return payload;
    throw ApiException('Unexpected response shape from $path');
  }

  /// DRF paginated lists arrive wrapped in {count, next, previous, results};
  /// plain arrays are accepted too.
  List<T> _listOf<T>(
    dynamic payload,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    List<dynamic>? raw;
    if (payload is List<dynamic>) {
      raw = payload;
    } else if (payload is Map<String, dynamic>) {
      raw = payload['results'] as List<dynamic>?;
    }
    if (raw == null) return <T>[];
    return raw.whereType<Map<String, dynamic>>().map(fromJson).toList();
  }

  /// Fetches every page of a DRF paginated list endpoint ({count, next,
  /// previous, results}) by following the absolute `next` links (fetched
  /// directly) up to [maxPages] requests. Returns the raw rows; callers map
  /// them through their model's fromJson. [query] applies to the first
  /// request only (the backend echoes filters into each `next` link).
  Future<List<Map<String, dynamic>>> _fetchAllPages(
    String path, {
    int maxPages = 5,
    Map<String, String>? query,
  }) async {
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
    String? next = path;
    Map<String, String>? nextQuery = query;
    for (var page = 0; page < maxPages && next != null; page++) {
      final dynamic payload =
          await _jsonRequest('GET', next, query: nextQuery);
      next = null;
      nextQuery = null;
      if (payload is Map<String, dynamic>) {
        rows.addAll(_listOf<Map<String, dynamic>>(payload, (row) => row));
        final dynamic rawNext = payload['next'];
        if (rawNext is String && rawNext.isNotEmpty) next = rawNext;
      } else if (payload is List<dynamic>) {
        // Plain (unpaginated) arrays arrive as one shot.
        rows.addAll(payload.whereType<Map<String, dynamic>>());
      }
    }
    return rows;
  }

  // -----------------------------------------------------------------------
  // Auth & profile
  // -----------------------------------------------------------------------

  /// POST /auth/register/, stores tokens, then loads the profile.
  Future<User> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> data = _asMap(
      await _jsonRequest(
        'POST',
        '/auth/register/',
        authorized: false,
        body: <String, dynamic>{
          'username': username,
          'email': email,
          'password': password,
        },
      ),
      '/auth/register/',
    );
    await _persistTokens(data['access'] as String?, data['refresh'] as String?);
    return me();
  }

  /// POST /auth/token/ with username+password; stores access and refresh,
  /// resolves with the fresh profile.
  Future<User> token({
    required String username,
    required String password,
  }) async {
    final Map<String, dynamic> data = _asMap(
      await _jsonRequest(
        'POST',
        '/auth/token/',
        authorized: false,
        body: <String, dynamic>{
          'username': username,
          'password': password,
        },
      ),
      '/auth/token/',
    );
    await _persistTokens(data['access'] as String?, data['refresh'] as String?);
    return me();
  }

  /// GET /me/
  Future<User> me() async =>
      User.fromJson(_asMap(await _jsonRequest('GET', '/me/'), '/me/'));

  /// PATCH /me/ with partial profile fields (e.g. display_name).
  Future<User> updateMe(Map<String, dynamic> fields) async => User.fromJson(
      _asMap(await _jsonRequest('PATCH', '/me/', body: fields), '/me/'));

  Future<User> uploadAvatar(String path) async {
    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', _uri('/me/avatar/'));
      request.headers['Accept'] = 'application/json';
      final access = await _ensureAccessToken();
      if (access != null && access.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $access';
      }
      request.files.add(await http.MultipartFile.fromPath('avatar', path));
      return http.Response.fromStream(await _http.send(request));
    }

    var body = await send();
    if (body.statusCode == 401 && await _refreshAccessToken()) {
      body = await send();
    }
    if (body.statusCode < 200 || body.statusCode >= 300) {
      throw _errorFrom(body);
    }
    return User.fromJson(_asMap(jsonDecode(body.body), '/me/avatar/'));
  }

  // -----------------------------------------------------------------------
  // Habits & streaks
  // -----------------------------------------------------------------------

  /// GET /habits/ - active habits with computed streaks, all pages.
  Future<List<Habit>> habits() async {
    final rows = await _fetchAllPages('/habits/');
    return rows.map(Habit.fromJson).toList(growable: false);
  }

  /// POST /habits/
  Future<Habit> createHabit({
    required String name,
    String description = '',
    String goalType = 'personal_development',
    String horizon = 'short',
    String icon = '',
    String color = 'primary',
    String category = 'mental',
    int graceDaysPerWeek = 0,
    List<int> scheduleDays = const <int>[1, 2, 3, 4, 5, 6, 7],
  }) async {
    final Map<String, dynamic> data = _asMap(
      await _jsonRequest(
        'POST',
        '/habits/',
        body: <String, dynamic>{
          'name': name,
          // Omit empty optionals so server-side defaults apply (e.g. icon).
          if (description.isNotEmpty) 'description': description,
          if (icon.isNotEmpty) 'icon': icon,
          'color': color,
          'category': category,
          'grace_days_per_week': graceDaysPerWeek,
          'schedule_days': scheduleDays,
        },
      ),
      '/habits/',
    );
    return Habit.fromJson(data);
  }

  /// GET /habits/today/ unwrapped to its {date, items} envelope.
  Future<TodayChecklist> todayChecklist() async => TodayChecklist.fromJson(
      _asMap(await _jsonRequest('GET', '/habits/today/'), '/habits/today/'));

  /// POST /habits/{id}/toggle/ - optional [date] defaults to today.
  Future<HabitToggleResult> toggleHabit(int id, {String? date}) async {
    final String path = '/habits/$id/toggle/';
    final Map<String, dynamic> data = _asMap(
      await _jsonRequest(
        'POST',
        path,
        body: date == null ? null : <String, dynamic>{'date': date},
      ),
      path,
    );
    return HabitToggleResult.fromJson(data);
  }

  /// GET /habits/{id}/history/?days=
  Future<HabitHistory> habitHistory(int id, {int days = 180}) async {
    final String path = '/habits/$id/history/';
    return HabitHistory.fromJson(_asMap(
      await _jsonRequest('GET', path,
          query: _cleanQuery(<String, String?>{'days': days.toString()})),
      path,
    ));
  }

  /// GET /habits/history_batch/?days= - every habit's history in one call
  /// (replaces a per-habit loop of [habitHistory]).
  Future<HabitHistoryBatch> habitHistoryBatch({int days = 180}) async =>
      HabitHistoryBatch.fromJson(_asMap(
        await _jsonRequest('GET', '/habits/history_batch/',
            query: _cleanQuery(<String, String?>{'days': days.toString()})),
        '/habits/history_batch/',
      ));

  /// GET /habits/heatmap_data/?weeks=
  Future<HeatmapData> heatmap({int weeks = 26}) async =>
      HeatmapData.fromJson(_asMap(
        await _jsonRequest('GET', '/habits/heatmap_data/',
            query: _cleanQuery(<String, String?>{'weeks': weeks.toString()})),
        '/habits/heatmap_data/',
      ));

  // -----------------------------------------------------------------------
  // Content hub
  // -----------------------------------------------------------------------

  /// GET /content/items/ with optional filters; follows every DRF page.
  Future<List<ContentItem>> contentItems({
    String? type,
    String? tag,
    String? search,
    String? source,
    String? sort,
    String? status,
    int? pageSize,
  }) async {
    final rows = await _fetchAllPages(
      '/content/items/',
      query: _cleanQuery(<String, String?>{
        'type': type,
        'tag': tag,
        'search': search,
        'source': source,
        'sort': sort,
        'status': status,
        if (pageSize != null) 'page_size': pageSize.toString(),
      }),
    );
    return rows.map(ContentItem.fromJson).toList(growable: false);
  }

  Future<ContentItem> viewContent(int id) async => ContentItem.fromJson(_asMap(
        await _jsonRequest('POST', '/content/items/$id/view/'),
        '/content/items/$id/view/',
      ));

  Future<ContentItem> readContent(int id) async => ContentItem.fromJson(_asMap(
        await _jsonRequest('POST', '/content/items/$id/read/'),
        '/content/items/$id/read/',
      ));

  Future<ContentItem> likeContent(int id) async => ContentItem.fromJson(_asMap(
        await _jsonRequest('POST', '/content/items/$id/like/'),
        '/content/items/$id/like/',
      ));

  Future<ContentItem> saveContent(int id) async => ContentItem.fromJson(_asMap(
        await _jsonRequest('POST', '/content/items/$id/save/'),
        '/content/items/$id/save/',
      ));

  /// GET /content/daily/ - deterministic rotation for [date] (or today).
  Future<DailyContent> dailyContent({String? date}) async =>
      DailyContent.fromJson(_asMap(
        await _jsonRequest('GET', '/content/daily/',
            query: _cleanQuery(<String, String?>{'date': date})),
        '/content/daily/',
      ));

  /// GET /content/motion/ - deterministic daily batch of up to ten quotes.
  Future<List<ContentItem>> motionQuotes({String? date}) async {
    final payload = _asMap(
      await _jsonRequest(
        'GET',
        '/content/motion/',
        query: _cleanQuery(<String, String?>{'date': date}),
      ),
      '/content/motion/',
    );
    return _listOf<ContentItem>(payload['items'], ContentItem.fromJson);
  }

  Future<void> updateMotionQuoteWidget(List<ContentItem> items) =>
      _motionQuoteChannel.invokeMethod<void>('update', <String, dynamic>{
        'texts': items.map((item) => item.text).toList(growable: false),
        'sources': items.map((item) => item.source).toList(growable: false),
      });

  // -----------------------------------------------------------------------
  // Priorities
  // -----------------------------------------------------------------------

  /// GET /priorities/?date= ordered by order; follows every DRF page.
  Future<List<Priority>> priorities({String? date}) async {
    final rows = await _fetchAllPages(
      '/priorities/',
      query: _cleanQuery(<String, String?>{'date': date}),
    );
    return rows.map(Priority.fromJson).toList(growable: false);
  }

  /// Alias of [priorities] used by pages (GET /priorities/).
  Future<List<Priority>> listPriorities() => priorities();

  /// POST /priorities/
  Future<Priority> createPriority({
    required String title,
    String? category,
    String? date,
    bool completed = false,
  }) async {
    final Map<String, dynamic> data = _asMap(
      await _jsonRequest(
        'POST',
        '/priorities/',
        body: <String, dynamic>{
          'title': title,
          'completed': completed,
          if (category != null && category.isNotEmpty) 'category': category,
          if (date != null && date.isNotEmpty) 'date': date,
        },
      ),
      '/priorities/',
    );
    return Priority.fromJson(data);
  }

  /// PATCH /priorities/{id}/ (e.g. toggle completion with {'completed': true}).
  Future<Priority> updatePriority(int id, Map<String, dynamic> fields) async {
    final String path = '/priorities/$id/';
    return Priority.fromJson(
        _asMap(await _jsonRequest('PATCH', path, body: fields), path));
  }

  /// DELETE /priorities/{id}/
  Future<void> deletePriority(int id) =>
      _jsonRequest('DELETE', '/priorities/$id/');

  /// POST /priorities/reorder/ with ordered_ids.
  Future<void> reorderPriorities(List<int> orderedIds) =>
      _jsonRequest('POST', '/priorities/reorder/',
          body: <String, dynamic>{'ordered_ids': orderedIds});

  // -----------------------------------------------------------------------
  // Goals
  // -----------------------------------------------------------------------

  /// GET /goals/?status= - follows every DRF page.
  Future<List<Goal>> goals({String? status}) async {
    final rows = await _fetchAllPages(
      '/goals/',
      query: _cleanQuery(<String, String?>{'status': status}),
    );
    return rows.map(Goal.fromJson).toList(growable: false);
  }

  /// Alias of [goals] used by pages (GET /goals/).
  Future<List<Goal>> listGoals() => goals();

  /// POST /goals/
  Future<Goal> createGoal({
    required String title,
    String description = '',
    String goalType = 'personal_development',
    String horizon = 'short',
    String? category,
    String? targetDate,
    int progress = 0,
    List<int> linkedHabitIds = const <int>[],
  }) async {
    final Map<String, dynamic> data = _asMap(
      await _jsonRequest(
        'POST',
        '/goals/',
        body: <String, dynamic>{
          'title': title,
          'description': description,
          'goal_type': goalType,
          'horizon': horizon,
          'progress': progress,
          'linked_habit_ids': linkedHabitIds,
          if (category != null && category.isNotEmpty) 'category': category,
          if (targetDate != null && targetDate.isNotEmpty)
            'target_date': targetDate,
        },
      ),
      '/goals/',
    );
    return Goal.fromJson(data);
  }

  /// PATCH /goals/{id}/ (status transitions included).
  Future<Goal> updateGoal(int id, Map<String, dynamic> fields) async {
    final String path = '/goals/$id/';
    return Goal.fromJson(
        _asMap(await _jsonRequest('PATCH', path, body: fields), path));
  }

  /// POST /goals/{id}/complete/ shortcut to status achieved.
  Future<Goal> completeGoal(int id) async {
    final String path = '/goals/$id/complete/';
    return Goal.fromJson(_asMap(await _jsonRequest('POST', path), path));
  }

  /// DELETE /goals/{id}/
  Future<void> deleteGoal(int id) => _jsonRequest('DELETE', '/goals/$id/');

  Future<WealthSummary> wealthSummary() async => WealthSummary.fromJson(
      _asMap(await _jsonRequest('GET', '/wealth/'), '/wealth/'));

  Future<void> updateWealthProfile({
    double? monthlyExpenses,
    String? startDate,
    String? currency,
  }) {
    final body = <String, dynamic>{
      if (monthlyExpenses != null)
        'monthly_expenses': monthlyExpenses.toStringAsFixed(2),
      if (startDate != null) 'start_date': startDate,
      if (currency != null && currency.isNotEmpty) 'currency': currency,
    };
    return _jsonRequest('PATCH', '/wealth/profile/', body: body);
  }

  Future<void> addIncomeStream({
    required String name,
    required double amount,
    String frequency = 'monthly',
  }) =>
      _jsonRequest('POST', '/wealth/income-streams/', body: <String, dynamic>{
        'name': name,
        'amount': amount.toStringAsFixed(2),
        'frequency': frequency,
      });

  Future<void> deleteIncomeStream(int id) =>
      _jsonRequest('DELETE', '/wealth/income-streams/$id/');

  Future<void> updateIncomeStream(
    int id, {
    required String name,
    required double amount,
    required String frequency,
  }) =>
      _jsonRequest('PATCH', '/wealth/income-streams/$id/',
          body: <String, dynamic>{
            'name': name,
            'amount': amount.toStringAsFixed(2),
            'frequency': frequency,
          });

  Future<void> addNetWorthSnapshot({
    required double amount,
    required String asOf,
  }) =>
      _jsonRequest('POST', '/wealth/net-worth/', body: <String, dynamic>{
        'amount': amount.toStringAsFixed(2),
        'as_of': asOf,
      });

  Future<void> deleteNetWorthSnapshot(int id) =>
      _jsonRequest('DELETE', '/wealth/net-worth/$id/');

  Future<void> updateNetWorthSnapshot(
    int id, {
    required double amount,
    required String asOf,
    String note = '',
  }) =>
      _jsonRequest('PATCH', '/wealth/net-worth/$id/', body: <String, dynamic>{
        'amount': amount.toStringAsFixed(2),
        'as_of': asOf,
        'note': note,
      });

  Future<void> addProfitEntry({
    required double amount,
    required String date,
    required String type,
    String note = '',
  }) =>
      _jsonRequest('POST', '/wealth/profit-entries/', body: <String, dynamic>{
        'amount': amount.toStringAsFixed(2),
        'date': date,
        'type': type,
        if (note.isNotEmpty) 'note': note,
      });

  Future<void> deleteProfitEntry(int id) =>
      _jsonRequest('DELETE', '/wealth/profit-entries/$id/');

  Future<void> updateProfitEntry(
    int id, {
    required double amount,
    required String date,
    required String type,
    String note = '',
  }) =>
      _jsonRequest('PATCH', '/wealth/profit-entries/$id/',
          body: <String, dynamic>{
            'amount': amount.toStringAsFixed(2),
            'date': date,
            'type': type,
            'note': note,
          });

  // -----------------------------------------------------------------------
  // Journal entries
  // -----------------------------------------------------------------------

  /// GET /journal/entries/?search= newest first, all pages.
  Future<List<JournalEntry>> journalEntries({String? search}) async {
    final rows = await _fetchAllPages(
      '/journal/entries/',
      query: _cleanQuery(<String, String?>{'search': search}),
    );
    return rows.map(JournalEntry.fromJson).toList(growable: false);
  }

  /// Alias of [journalEntries] used by pages (GET /journal/entries/).
  Future<List<JournalEntry>> listJournalEntries({String? search}) =>
      journalEntries(search: search);

  /// GET /journal/entries/?search= with a positional query term.
  Future<List<JournalEntry>> searchJournalEntries(String query) =>
      journalEntries(search: query);

  /// POST /journal/entries/
  Future<JournalEntry> createJournalEntry({
    required String title,
    required String body,
    String? mood,
  }) async {
    final Map<String, dynamic> data = _asMap(
      await _jsonRequest(
        'POST',
        '/journal/entries/',
        body: <String, dynamic>{
          'title': title,
          'body': body,
          if (mood != null && mood.isNotEmpty) 'mood': mood,
        },
      ),
      '/journal/entries/',
    );
    return JournalEntry.fromJson(data);
  }

  /// PATCH /journal/entries/{id}/
  Future<JournalEntry> updateJournalEntry(
      int id, Map<String, dynamic> fields) async {
    final String path = '/journal/entries/$id/';
    return JournalEntry.fromJson(
        _asMap(await _jsonRequest('PATCH', path, body: fields), path));
  }

  /// DELETE /journal/entries/{id}/
  Future<void> deleteJournalEntry(int id) =>
      _jsonRequest('DELETE', '/journal/entries/$id/');

  // -----------------------------------------------------------------------
  // Memories / Achievements
  // -----------------------------------------------------------------------

  /// GET /memories/ - all pages.
  Future<List<Memory>> memories() async {
    final rows = await _fetchAllPages('/memories/');
    return rows.map(Memory.fromJson).toList(growable: false);
  }

  /// Alias of [memories] used by pages (GET /memories/).
  Future<List<Memory>> listMemories() => memories();

  /// POST /memories/ - JSON without a photo, multipart with one.
  Future<Memory> createMemory({
    required String title,
    String description = '',
    required String date,
    String? photoPath,
  }) async {
    if (photoPath == null || photoPath.isEmpty) {
      final Map<String, dynamic> data = _asMap(
        await _jsonRequest(
          'POST',
          '/memories/',
          body: <String, dynamic>{
            'title': title,
            'description': description,
            'date': date,
          },
        ),
        '/memories/',
      );
      return Memory.fromJson(data);
    }
    http.Response response = await _sendMultipartMemory(
      title: title,
      description: description,
      date: date,
      photoPath: photoPath,
    );
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      response = await _sendMultipartMemory(
        title: title,
        description: description,
        date: date,
        photoPath: photoPath,
      );
    }
    if (response.statusCode == 401) {
      await logout();
      throw ApiException('Your session expired. Please sign in again.',
          status: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFrom(response);
    }
    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return Memory.fromJson(_asMap(decoded, '/memories/'));
  }

  Future<http.Response> _sendMultipartMemory({
    required String title,
    required String description,
    required String date,
    required String photoPath,
  }) async {
    final http.MultipartRequest request =
        http.MultipartRequest('POST', _uri('/memories/'));
    request.headers['Accept'] = 'application/json';
    final String? access = await _ensureAccessToken();
    if (access != null && access.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $access';
    }
    request.fields['title'] = title;
    request.fields['description'] = description;
    request.fields['date'] = date;
    request.files.add(await http.MultipartFile.fromPath('photo', photoPath));
    return http.Response.fromStream(await _http.send(request));
  }

  /// PATCH /memories/{id}/
  Future<Memory> updateMemory(int id, Map<String, dynamic> fields) async {
    final String path = '/memories/$id/';
    return Memory.fromJson(
        _asMap(await _jsonRequest('PATCH', path, body: fields), path));
  }

  /// DELETE /memories/{id}/
  Future<void> deleteMemory(int id) => _jsonRequest('DELETE', '/memories/$id/');

  // -----------------------------------------------------------------------
  // Reminders
  // -----------------------------------------------------------------------

  /// GET /reminders/ - all pages.
  Future<List<Reminder>> reminders() async {
    final rows = await _fetchAllPages('/reminders/');
    return rows.map(Reminder.fromJson).toList(growable: false);
  }

  /// POST /reminders/ ([time] as HH:MM, [days] Mon=0, empty means daily).
  Future<Reminder> createReminder({
    required String title,
    String message = '',
    required String time,
    List<int> days = const <int>[],
    String category = 'health',
  }) async {
    final Map<String, dynamic> data = _asMap(
      await _jsonRequest(
        'POST',
        '/reminders/',
        body: <String, dynamic>{
          'title': title,
          'message': message,
          'time': time,
          'days': days,
          'category': category,
        },
      ),
      '/reminders/',
    );
    return Reminder.fromJson(data);
  }

  /// PATCH /reminders/{id}/
  Future<Reminder> updateReminder(int id, Map<String, dynamic> fields) async {
    final String path = '/reminders/$id/';
    return Reminder.fromJson(
        _asMap(await _jsonRequest('PATCH', path, body: fields), path));
  }

  /// DELETE /reminders/{id}/
  Future<void> deleteReminder(int id) =>
      _jsonRequest('DELETE', '/reminders/$id/');

  // -----------------------------------------------------------------------
  // Notification feed (pushed Signo events)
  // -----------------------------------------------------------------------

  /// GET /notifications/ - newest first, all pages.
  Future<List<AppNotification>> notifications() async {
    final rows = await _fetchAllPages('/notifications/');
    return rows.map(AppNotification.fromJson).toList(growable: false);
  }

  /// POST /notifications/read_all/ - clear the unread badge.
  Future<void> markAllNotificationsRead() =>
      _jsonRequest('POST', '/notifications/read_all/');
}

/// Convenience global used by some pages.
final api = ApiClient.instance;