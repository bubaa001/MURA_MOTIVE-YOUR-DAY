/// In-app updater: checks the release manifest on launch and offers to
/// download + install a newer build of MURA.
///
/// Backend: GET /api/v1/update/ returns {version_code, version_name, notes,
/// apk_url, released_at} for the newest published build (see
/// backend/updates/ + 'manage.py publish_release').
library;

import 'dart:async';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class UpdateManifest {
  const UpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.notes,
    required this.apkUrl,
  });

  final int versionCode;
  final String versionName;
  final String notes;
  final String apkUrl;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) => UpdateManifest(
        versionCode: (json['version_code'] as num?)?.toInt() ?? 0,
        versionName: (json['version_name'] as String?) ?? '',
        notes: (json['notes'] as String?) ?? '',
        apkUrl: (json['apk_url'] as String?) ?? '',
      );
}

/// Fetch the newest published release; null when none exists or the server
/// is unreachable (never throws).
Future<UpdateManifest?> fetchUpdateManifest() async {
  final http.Client client = http.Client();
  try {
    final http.Response response = await client
        .get(
          Uri.parse(ApiClient.baseUrl + '/update/'),
          headers: const <String, String>{
            'Accept': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) return null;
    final UpdateManifest manifest = UpdateManifest.fromJson(decoded);
    if (manifest.versionCode <= 0 || manifest.apkUrl.isEmpty) return null;
    return manifest;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// True when [remote] is newer than the installed build.
Future<bool> isNewer(UpdateManifest remote) async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final int installed = int.tryParse(info.buildNumber) ?? 0;
    return remote.versionCode > installed;
  } catch (_) {
    return false;
  }
}

/// One prompt per app session.
bool _promptedThisSession = false;

/// Module-level channel shared by the dialogs.
final MethodChannel _updaterChannel = MethodChannel('com.bubaa.mura/updater');

/// Set by whichever dialog is open so the native "download completed"
/// broadcast routes straight to it (no polling for the finish step).
Future<void> Function(int downloadId)? _downloadCompletedHandler;
bool _completionListenerReady = false;

void _ensureCompletionListener() {
  if (_completionListenerReady) return;
  _completionListenerReady = true;
  _updaterChannel.setMethodCallHandler((MethodCall call) async {
    if (call.method == 'onDownloadComplete') {
      final Object? raw = call.arguments;
      final int id = raw is num ? raw.toInt() : -1;
      final Future<void> Function(int downloadId)? handler =
          _downloadCompletedHandler;
      if (handler != null && id > 0) {
        await handler(id);
      }
    }
    return null;
  });
}

/// Check once for a newer build and, when found, offer the update.
Future<void> maybePromptForUpdate() async {
  if (_promptedThisSession) return;
  final UpdateManifest? manifest = await fetchUpdateManifest();
  if (manifest == null) return;
  if (!await isNewer(manifest)) return;

  // Respect a 24h "remind me later".
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final int snoozed = prefs.getInt('mura.update.snoozedAt') ?? 0;
  if (DateTime.now().millisecondsSinceEpoch < snoozed) return;

  _promptedThisSession = true;
  final BuildContext? context = muraNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(manifest: manifest),
  );
}

Future<void> snoozeUpdatePrompt() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setInt(
    'mura.update.snoozedAt',
    DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
  );
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.manifest});

  final UpdateManifest manifest;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  bool _needPermission = false;
  double _progress = 0;
  String _status = '';
  String _progressLabel = '';
  String? _error;
  Timer? _poll;
  int? _downloadId;

  @override
  void initState() {
    super.initState();
    _ensureCompletionListener();
    _downloadCompletedHandler = _handleDownloadComplete;
  }

  Future<void> _handleDownloadComplete(int id) async {
    if (!mounted) return;
    await _finishDownload(id);
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (identical(_downloadCompletedHandler, _handleDownloadComplete)) {
      _downloadCompletedHandler = null;
    }
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _status = 'Starting download…';
    });
    try {
      final int? id = await _updaterChannel.invokeMethod<int>(
        'startDownload',
        <String, String>{
          'url': widget.manifest.apkUrl,
          'filename': 'mura-' + widget.manifest.versionName + '.apk',
        },
      );
      if (id == null) throw ApiException('Could not start the download.');
      _downloadId = id;
      if (!mounted) return;
      setState(() {
        _status = 'Downloading in the background… you can keep using MURA.';
      });
      // Poll the system download (keeps running if this dialog closes).
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollStatus());
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = 'Could not start the download: '
              + (e.message ?? 'unknown error');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = 'Update failed: ' + friendlyError(e);
        });
      }
    }
  }

  Future<void> _pollStatus() async {
    final int? id = _downloadId;
    if (id == null) return;
    try {
      final Map<Object?, Object?> status = await _updaterChannel
          .invokeMethod<Map<Object?, Object?>>('downloadStatus', <String, Object>{
        'id': id,
      }) ?? <Object?, Object?>{};
      if (!mounted) return;
      final String state = status['status'] as String? ?? 'pending';
      if (state == 'running' || state == 'paused') {
        final int bytes = (status['bytes'] as num?)?.toInt() ?? 0;
        final int total = (status['total'] as num?)?.toInt() ?? 0;
        final double progress = (status['progress'] as num? ?? 0).toDouble();
        String label;
        if (total > 0) {
          label = (progress * 100).round().toString() + '%';
        } else if (bytes > 0) {
          label = (bytes / 1048576).toStringAsFixed(1) + ' MB downloaded';
        } else {
          label = 'Starting…';
        }
        setState(() {
          _progress = progress;
          _progressLabel = label;
        });
      } else if (state == 'success') {
        _poll?.cancel();
        await _finishDownload(id);
      } else if (state == 'failed' || state == 'gone') {
        _poll?.cancel();
        if (mounted) {
          setState(() {
            _downloading = false;
            _error = 'The download failed. Please try again.';
          });
        }
      }
    } catch (_) {
      // Poll is best-effort; the system notification still tracks progress.
    }
  }

  Future<void> _finishDownload(int id) async {
    if (!mounted) return;
    setState(() => _status = 'Installing…');
    try {
      final Object? outcome = await _updaterChannel.invokeMethod<Object?>(
        'finishDownload',
        <String, Object>{'id': id},
      );
      if (!mounted) return;
      if (outcome == 'need_permission') {
        setState(() {
          _downloading = false;
          _needPermission = true;
          _status = '';
        });
        return; // User grants it; install resumes automatically on return.
      }
      // Installer took over (or nothing left to do).
      Navigator.of(context).pop();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = 'Could not open the installer: '
              + (e.message ?? 'unknown error');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = 'Update failed: ' + friendlyError(e);
        });
      }
    }
  }

  Future<void> _openInstallSettings() async {
    try {
      await _updaterChannel.invokeMethod<void>('openInstallSettings');
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open settings: '
            + (e.message ?? 'unknown error'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        _needPermission
            ? 'One more step'
            : 'MURA ' + widget.manifest.versionName + ' is ready',
        style: TextStyle(
            color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: _error != null
          ? Text(_error!,
              style: TextStyle(color: scheme.error, fontSize: 13.5))
          : _needPermission
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text('The update is downloaded. Android needs your '
                        'permission for MURA to install it.',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13.5,
                            height: 1.45)),
                    const SizedBox(height: 8),
                    Text('Tap the button, then switch "Allow from this '
                        'source" ON for MURA. The update continues '
                        'automatically when you come back.',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12.5,
                            height: 1.4)),
                  ],
                )
              : _downloading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(_status,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 13)),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(value: _progress),
                        const SizedBox(height: 6),
                        Text(
                          (_progressLabel.isEmpty
                                  ? (_progress * 100).round().toString() + '%'
                                  : _progressLabel) +
                              '  ·  runs in the background',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Text('You can close this and keep using MURA — the '
                            'download continues and finishes the install '
                            'when it is done.',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11.5,
                                height: 1.4)),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (widget.manifest.notes.trim().isNotEmpty) ...[
                          Text(widget.manifest.notes.trim(),
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13.5,
                                  height: 1.4)),
                          const SizedBox(height: 14),
                        ],
                        Text('This update downloads in the background '
                            '(~50 MB) and installs when finished. You can '
                            'keep using the app.',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12.5)),
                      ],
                    ),
      actions: _error != null
          ? <Widget>[
              TextButton(
                onPressed: () {
                  setState(() => _error = null);
                  snoozeUpdatePrompt();
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _progress = 0;
                  });
                  _startDownload();
                },
                child: const Text('Try again'),
              ),
            ]
          : _needPermission
              ? <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      snoozeUpdatePrompt();
                    },
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _openInstallSettings,
                    child: const Text('Open settings'),
                  ),
                ]
              : _downloading
                  ? <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Downloading… Close'),
                      ),
                    ]
                  : <Widget>[
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          snoozeUpdatePrompt();
                        },
                        child: const Text('Later'),
                      ),
                      FilledButton(
                        onPressed: _startDownload,
                        child: const Text('Update now'),
                      ),
                    ],
    );
  }
}


/// One resume prompt per session.
bool _resumePromptShown = false;

/// Called when the app opens: if a backgrounded update download finished
/// while we were away, offer to install it now.
Future<void> maybeFinishPendingUpdate() async {
  if (_resumePromptShown) return;
  Map<Object?, Object?>? pending;
  try {
    pending =
        await _updaterChannel.invokeMethod<Map<Object?, Object?>>('pendingDownload');
  } catch (_) {
    return;
  }
  if (pending == null) return;
  final int id = (pending['id'] as num?)?.toInt() ?? -1;
  if (id <= 0) return;

  final Map<Object?, Object?> status = await _updaterChannel
          .invokeMethod<Map<Object?, Object?>>(
        'downloadStatus',
        <String, Object>{'id': id},
      ) ??
      const <Object?, Object?>{};
  if ((status['status'] as String?) != 'success') return; // still running/failed

  _resumePromptShown = true;
  final BuildContext? context = muraNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _InstallReadyDialog(downloadId: id),
  );
}

class _InstallReadyDialog extends StatefulWidget {
  const _InstallReadyDialog({required this.downloadId});

  final int downloadId;

  @override
  State<_InstallReadyDialog> createState() => _InstallReadyDialogState();
}

class _InstallReadyDialogState extends State<_InstallReadyDialog> {
  bool _installing = false;
  bool _needPermission = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ensureCompletionListener();
    _downloadCompletedHandler = _handleComplete;
  }

  Future<void> _handleComplete(int id) async {
    if (!mounted) return;
    await _installNow();
  }

  @override
  void dispose() {
    if (identical(_downloadCompletedHandler, _handleComplete)) {
      _downloadCompletedHandler = null;
    }
    super.dispose();
  }

  Future<void> _installNow() async {
    setState(() => _installing = true);
    try {
      final Object? outcome = await _updaterChannel.invokeMethod<Object?>(
        'finishDownload',
        <String, Object>{'id': widget.downloadId},
      );
      if (!mounted) return;
      if (outcome == 'need_permission') {
        setState(() {
          _installing = false;
          _needPermission = true;
        });
        return;
      }
      Navigator.of(context).pop(); // installer took over
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = 'Could not open the installer: '
              + (e.message ?? 'unknown error');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = 'Update failed: ' + friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        _needPermission ? 'One more step' : 'Update downloaded',
        style: TextStyle(
            color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: _error != null
          ? Text(_error!,
              style: TextStyle(color: scheme.error, fontSize: 13.5))
          : _needPermission
              ? Text('Android needs your permission for MURA to install the '
                  'update. Tap the button and switch "Allow from this source" '
                  'ON — the install continues when you come back.',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13.5,
                      height: 1.45))
              : _installing
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    )
                  : Text('The new build finished downloading in the '
                      'background. Install it now?',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13.5,
                          height: 1.45)),
      actions: _error != null
          ? <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() => _error = null);
                  _installNow();
                },
                child: const Text('Try again'),
              ),
            ]
          : _needPermission
              ? <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await _updaterChannel.invokeMethod<void>('openInstallSettings');
                      } catch (_) {}
                    },
                    child: const Text('Open settings'),
                  ),
                ]
              : _installing
                  ? null
                  : <Widget>[
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          snoozeUpdatePrompt();
                        },
                        child: const Text('Not now'),
                      ),
                      FilledButton(
                        onPressed: _installNow,
                        child: const Text('Install'),
                      ),
                    ],
    );
  }
}

