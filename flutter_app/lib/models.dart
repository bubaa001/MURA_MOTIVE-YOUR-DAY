/// Plain Dart model classes mirroring docs/api-contract.md (v1).
///
/// Dates stay ISO-8601 strings, ids are ints, and every model exposes
/// fromJson / toJson using the wire-format snake_case keys.
library;

import 'package:flutter/material.dart' show IconData, Icons;

// ---------------------------------------------------------------------------
// Coercion helpers (the backend may omit computed fields or send numbers
// formatted as strings; parsers below tolerate both).
// ---------------------------------------------------------------------------

int _toInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

int? _toIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double _toDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

bool _toBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String v = value.trim().toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
  }
  return fallback;
}

String _toString(dynamic value, {String fallback = ''}) =>
    value == null ? fallback : value.toString();

String? _toStringOrNull(dynamic value) {
  if (value == null) return null;
  final String s = value.toString();
  return s.isEmpty ? null : s;
}

List<int> _toIntList(dynamic value) => value is List
    ? value.map((dynamic e) => _toInt(e)).toList(growable: false)
    : <int>[];

List<T> _fromJsonList<T>(
  dynamic value,
  T Function(Map<String, dynamic> json) fromJson,
) =>
    value is List
        ? value
            .whereType<Map<String, dynamic>>()
            .map(fromJson)
            .toList(growable: false)
        : <T>[];

// ---------------------------------------------------------------------------
// Auth / profile
// ---------------------------------------------------------------------------

class User {
  const User({
    required this.id,
    required this.username,
    this.email = '',
    this.firstName = '',
    this.displayName = '',
    this.dateJoined = '',
    this.avatar,
    this.plan = 'free',
    this.pushTopic = '',
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: _toInt(json['id']),
        username: _toString(json['username']),
        email: _toString(json['email']),
        firstName: _toString(json['first_name']),
        displayName: _toString(json['display_name']),
        dateJoined: _toString(json['date_joined']),
        avatar: _toStringOrNull(json['avatar']),
        plan: _toString(json['plan'], fallback: 'free'),
        pushTopic: _toString(json['push_topic']),
      );

  final int id;
  final String username;
  final String email;
  final String firstName;
  final String displayName;
  final String dateJoined;
  final String? avatar;

  /// Subscription tier from /me/: "free" | "premium".
  final String plan;

  /// Server-assigned push topic (empty when unset), for upcoming premium work.
  final String pushTopic;

  String get effectiveName => displayName.isNotEmpty ? displayName : username;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'username': username,
        'email': email,
        'first_name': firstName,
        'display_name': displayName,
        'date_joined': dateJoined,
      };
}

// ---------------------------------------------------------------------------
// Habits & streaks
// ---------------------------------------------------------------------------

class Habit {
  const Habit({
    required this.id,
    required this.name,
    this.description = '',
    this.goalType = 'personal_development',
    this.horizon = 'short',
    this.icon = '',
    this.color = 'primary',
    this.category = 'mental',
    this.graceDaysPerWeek = 0,
    this.scheduleDays = const <int>[1, 2, 3, 4, 5, 6, 7],
    this.isActive = true,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.completionRate30d = 0,
    this.createdAt = '',
  });

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: _toInt(json['id']),
        name: _toString(json['name']),
        description: _toString(json['description']),
        goalType:
            _toString(json['goal_type'], fallback: 'personal_development'),
        horizon: _toString(json['horizon'], fallback: 'short'),
        icon: _toString(json['icon']),
        color: _toString(json['color'], fallback: 'primary'),
        category: _toString(json['category'], fallback: 'mental'),
        graceDaysPerWeek: _toInt(json['grace_days_per_week']),
        scheduleDays: _toIntList(json['schedule_days']).isEmpty
            ? const <int>[1, 2, 3, 4, 5, 6, 7]
            : _toIntList(json['schedule_days']),
        isActive: _toBool(json['is_active'], fallback: true),
        currentStreak: _toInt(json['current_streak']),
        bestStreak: _toInt(json['best_streak']),
        completionRate30d: _toInt(json['completion_rate_30d']),
        createdAt: _toString(json['created_at']),
      );

  final int id;
  final String name;
  final String description;
  final String goalType;
  final String horizon;
  final String icon;
  final String color;
  final String category;
  final int graceDaysPerWeek;
  final List<int> scheduleDays;
  final bool isActive;
  final int currentStreak;
  final int bestStreak;
  final int completionRate30d;
  final String createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'goal_type': goalType,
        'horizon': horizon,
        'icon': icon,
        'color': color,
        'category': category,
        'grace_days_per_week': graceDaysPerWeek,
        'schedule_days': scheduleDays,
        'is_active': isActive,
        'current_streak': currentStreak,
        'best_streak': bestStreak,
        'completion_rate_30d': completionRate30d,
        'created_at': createdAt,
      };
}

/// One row of GET /habits/today/ items.
class TodayItem {
  const TodayItem({
    required this.habitId,
    required this.name,
    this.icon = '',
    this.color = 'primary',
    this.category = 'mental',
    this.completed = false,
    this.logId,
  });

  factory TodayItem.fromJson(Map<String, dynamic> json) => TodayItem(
        habitId: _toInt(json['habit_id']),
        name: _toString(json['name']),
        icon: _toString(json['icon']),
        color: _toString(json['color'], fallback: 'primary'),
        category: _toString(json['category'], fallback: 'mental'),
        completed: _toBool(json['completed']),
        logId: _toIntOrNull(json['log_id']),
      );

  final int habitId;
  final String name;
  final String icon;
  final String color;
  final String category;
  final bool completed;
  final int? logId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'habit_id': habitId,
        'name': name,
        'icon': icon,
        'color': color,
        'category': category,
        'completed': completed,
        'log_id': logId,
      };
}

/// Unwrapped envelope of GET /habits/today/ ({date, items}).
class TodayChecklist {
  const TodayChecklist({required this.date, this.items = const <TodayItem>[]});

  factory TodayChecklist.fromJson(Map<String, dynamic> json) => TodayChecklist(
        date: _toString(json['date']),
        items: _fromJsonList(json['items'], TodayItem.fromJson),
      );

  final String date;
  final List<TodayItem> items;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'items': items.map((TodayItem item) => item.toJson()).toList(),
      };
}

/// {date, completed} row of the per-habit history feed.
class HabitDay {
  const HabitDay({required this.date, this.completed = false});

  factory HabitDay.fromJson(Map<String, dynamic> json) => HabitDay(
        date: _toString(json['date']),
        completed: _toBool(json['completed']),
      );

  final String date;
  final bool completed;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'completed': completed,
      };
}

/// Envelope of GET /habits/{id}/history/: {days, streaks}.
class HabitHistory {
  const HabitHistory({
    this.days = const <HabitDay>[],
    this.currentStreak = 0,
    this.bestStreak = 0,
  });

  factory HabitHistory.fromJson(Map<String, dynamic> json) {
    final dynamic rawStreaks = json['streaks'];
    final Map<String, dynamic> streaks = rawStreaks is Map<String, dynamic>
        ? rawStreaks
        : const <String, dynamic>{};
    return HabitHistory(
      days: _fromJsonList(json['days'], HabitDay.fromJson),
      currentStreak: _toInt(streaks['current']),
      bestStreak: _toInt(streaks['best']),
    );
  }

  final List<HabitDay> days;
  final int currentStreak;
  final int bestStreak;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'days': days.map((HabitDay day) => day.toJson()).toList(),
        'streaks': <String, dynamic>{
          'current': currentStreak,
          'best': bestStreak,
        },
      };
}

/// Envelope of `GET /habits/history_batch/?days=` :
/// `{days_span, habits: {"<habit_id>": {days, streaks}}}`. One call replaces
/// a per-habit loop of `GET /habits/{id}/history/`.
class HabitHistoryBatch {
  const HabitHistoryBatch({
    this.daysSpan = 0,
    this.histories = const <int, HabitHistory>{},
  });

  factory HabitHistoryBatch.fromJson(Map<String, dynamic> json) {
    final Map<int, HabitHistory> parsed = <int, HabitHistory>{};
    final dynamic rawHabits = json['habits'];
    if (rawHabits is Map<String, dynamic>) {
      rawHabits.forEach((String key, dynamic value) {
        final int? id = int.tryParse(key);
        if (id != null && value is Map<String, dynamic>) {
          parsed[id] = HabitHistory.fromJson(value);
        }
      });
    }
    return HabitHistoryBatch(
      daysSpan: _toInt(json['days_span']),
      histories: parsed,
    );
  }

  final int daysSpan;

  /// habitId -> its {days, streaks} history.
  final Map<int, HabitHistory> histories;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'days_span': daysSpan,
        'habits': <String, dynamic>{
          for (final MapEntry<int, HabitHistory> entry in histories.entries)
            '${entry.key}': entry.value.toJson(),
        },
      };
}

/// Flat result of POST /habits/{id}/toggle/.
class HabitToggleResult {
  const HabitToggleResult({
    required this.habitId,
    required this.date,
    required this.completed,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.completionRate30d = 0,
    this.completedToday = false,
  });

  factory HabitToggleResult.fromJson(Map<String, dynamic> json) =>
      HabitToggleResult(
        habitId: _toInt(json['habit_id']),
        date: _toString(json['date']),
        completed: _toBool(json['completed']),
        currentStreak: _toInt(json['current_streak']),
        bestStreak: _toInt(json['best_streak']),
        completionRate30d: _toInt(json['completion_rate_30d']),
        completedToday: _toBool(json['completed_today']),
      );

  final int habitId;
  final String date;

  /// Authoritative for the toggled day.
  final bool completed;
  final int currentStreak;
  final int bestStreak;
  final int completionRate30d;

  /// Always refers to today, regardless of which day was toggled.
  final bool completedToday;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'habit_id': habitId,
        'date': date,
        'completed': completed,
        'current_streak': currentStreak,
        'best_streak': bestStreak,
        'completion_rate_30d': completionRate30d,
        'completed_today': completedToday,
      };
}

// ---------------------------------------------------------------------------
// Heatmap
// ---------------------------------------------------------------------------

/// One calendar square: intensity bucket 0..4 of the day's completion ratio.
class HeatmapCell {
  const HeatmapCell({
    required this.date,
    this.ratio = 0,
    this.level = 0,
  });

  factory HeatmapCell.fromJson(Map<String, dynamic> json) => HeatmapCell(
        date: _toString(json['date']),
        ratio: _toDouble(json['ratio']),
        level: _toInt(json['level']),
      );

  final String date;
  final double ratio;
  final int level;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'ratio': ratio,
        'level': level,
      };
}

class HeatmapWeek {
  const HeatmapWeek({
    required this.weekStart,
    this.days = const <HeatmapCell>[],
  });

  factory HeatmapWeek.fromJson(Map<String, dynamic> json) => HeatmapWeek(
        weekStart: _toString(json['week_start']),
        days: _fromJsonList(json['days'], HeatmapCell.fromJson),
      );

  final String weekStart;
  final List<HeatmapCell> days;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'week_start': weekStart,
        'days': days.map((HeatmapCell cell) => cell.toJson()).toList(),
      };
}

/// Envelope of GET /habits/heatmap_data/: {weeks: [...]}.
class HeatmapData {
  const HeatmapData({this.weeks = const <HeatmapWeek>[]});

  factory HeatmapData.fromJson(Map<String, dynamic> json) => HeatmapData(
        weeks: _fromJsonList(json['weeks'], HeatmapWeek.fromJson),
      );

  final List<HeatmapWeek> weeks;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'weeks': weeks.map((HeatmapWeek week) => week.toJson()).toList(),
      };
}

// ---------------------------------------------------------------------------
// Content hub (quotes / prayers / philosophies)
// ---------------------------------------------------------------------------

class ContentItem {
  const ContentItem({
    required this.id,
    required this.type,
    required this.text,
    this.source = '',
    this.tags = const <String>[],
    this.createdAt = '',
    this.image,
    this.viewCount = 0,
    this.likeCount = 0,
    this.viewed = false,
    this.read = false,
    this.liked = false,
    this.saved = false,
  });

  factory ContentItem.fromJson(Map<String, dynamic> json) => ContentItem(
        id: _toInt(json['id']),
        type: _toString(json['type']),
        text: _toString(json['text']),
        source: _toString(json['source']),
        tags: json['tags'] is List
            ? (json['tags'] as List<Object?>)
                .map<String>((dynamic e) => e.toString())
                .toList(growable: false)
            : const <String>[],
        createdAt: _toString(json['created_at']),
        image: _toStringOrNull(json['image']),
        viewCount: _toInt(json['view_count']),
        likeCount: _toInt(json['like_count']),
        viewed: _toBool(json['viewed']),
        read: _toBool(json['read']),
        liked: _toBool(json['liked']),
        saved: _toBool(json['saved']),
      );

  final int id;
  final String type;
  final String text;
  final String source;
  final List<String> tags;
  final String createdAt;
  final String? image;
  final int viewCount;
  final int likeCount;
  final bool viewed;
  final bool read;
  final bool liked;
  final bool saved;

  ContentItem copyWith({bool? saved, bool? liked}) => ContentItem(
        id: id,
        type: type,
        text: text,
        source: source,
        tags: tags,
        createdAt: createdAt,
        image: image,
        viewCount: viewCount,
        likeCount: likeCount,
        viewed: viewed,
        read: read,
        liked: liked ?? this.liked,
        saved: saved ?? this.saved,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'text': text,
        'source': source,
        'tags': tags,
        'created_at': createdAt,
        'view_count': viewCount,
        'like_count': likeCount,
        'viewed': viewed,
        'read': read,
        'liked': liked,
        'saved': saved,
      };
}

/// Envelope of GET /content/daily/ - any slot may be null.
class DailyContent {
  const DailyContent({
    required this.date,
    this.quote,
    this.insight,
    this.philosophy,
  });

  factory DailyContent.fromJson(Map<String, dynamic> json) {
    ContentItem? slot(String key) {
      final dynamic raw = json[key];
      return raw is Map<String, dynamic> ? ContentItem.fromJson(raw) : null;
    }

    return DailyContent(
      date: _toString(json['date']),
      quote: slot('quote'),
      // Spiritual insight (formerly the prayer slot).
      insight: slot('insight'),
      philosophy: slot('philosophy'),
    );
  }

  final String date;
  final ContentItem? quote;
  final ContentItem? insight;
  final ContentItem? philosophy;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'quote': quote?.toJson(),
        'insight': insight?.toJson(),
        'philosophy': philosophy?.toJson(),
      };
}

// ---------------------------------------------------------------------------
// Priorities
// ---------------------------------------------------------------------------

class Priority {
  const Priority({
    required this.id,
    required this.title,
    this.category = '',
    this.order = 0,
    this.completed = false,
    this.date = '',
    this.createdAt = '',
  });

  factory Priority.fromJson(Map<String, dynamic> json) => Priority(
        id: _toInt(json['id']),
        title: _toString(json['title']),
        category: _toString(json['category']),
        order: _toInt(json['order']),
        completed: _toBool(json['completed']),
        date: _toString(json['date']),
        createdAt: _toString(json['created_at']),
      );

  final int id;
  final String title;
  final String category;
  final int order;
  final bool completed;
  final String date;
  final String createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'category': category,
        'order': order,
        'completed': completed,
        'date': date,
        'created_at': createdAt,
      };
}

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------

class Goal {
  const Goal({
    required this.id,
    required this.title,
    this.description = '',
    this.goalType = 'personal_development',
    this.horizon = 'short',
    this.category = '',
    this.targetDate,
    this.status = 'active',
    this.progress = 0,
    this.linkedHabitIds = const <int>[],
    this.createdAt = '',
  });

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: _toInt(json['id']),
        title: _toString(json['title']),
        description: _toString(json['description']),
        goalType:
            _toString(json['goal_type'], fallback: 'personal_development'),
        horizon: _toString(json['horizon'], fallback: 'short'),
        category: _toString(json['category']),
        targetDate: _toStringOrNull(json['target_date']),
        status: _toString(json['status'], fallback: 'active'),
        progress: _toInt(json['progress']),
        linkedHabitIds: _toIntList(json['linked_habit_ids']),
        createdAt: _toString(json['created_at']),
      );

  final int id;
  final String title;
  final String description;
  final String goalType;
  final String horizon;
  final String category;
  final String? targetDate;
  final String status;
  final int progress;
  final List<int> linkedHabitIds;
  final String createdAt;

  bool get isAchieved => status == 'achieved';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'goal_type': goalType,
        'horizon': horizon,
        'category': category,
        'target_date': targetDate,
        'status': status,
        'progress': progress,
        'linked_habit_ids': linkedHabitIds,
        'created_at': createdAt,
      };
}

class WealthSummary {
  const WealthSummary({
    this.currency = 'USD',
    this.monthlyIncome = 0,
    this.monthlyExpenses = 0,
    this.monthlySavings = 0,
    this.savingsRate = 0,
    this.netWorth,
    this.netWorthChange,
    this.journeyStartDate,
    this.profitSinceStart = 0,
    this.lossSinceStart = 0,
    this.netResultSinceStart = 0,
    this.averageMonthlyProfit = 0,
    this.netProfitMargin = 0,
    this.expenseRatio = 0,
    this.incomeStreams = const <IncomeStream>[],
    this.profitEntries = const <ProfitEntry>[],
    this.netWorthHistory = const <NetWorthSnapshot>[],
  });

  factory WealthSummary.fromJson(Map<String, dynamic> json) {
    final netWorth = json['net_worth'];
    return WealthSummary(
      currency: _toString(json['currency'], fallback: 'USD'),
      monthlyIncome: _toDouble(json['monthly_income']),
      monthlyExpenses: _toDouble(json['monthly_expenses']),
      monthlySavings: _toDouble(json['monthly_savings']),
      savingsRate: _toDouble(json['savings_rate']),
      netWorth: netWorth is Map<String, dynamic>
          ? _toDouble(netWorth['amount'])
          : null,
      netWorthChange: json['net_worth_change'] == null
          ? null
          : _toDouble(json['net_worth_change']),
      journeyStartDate: _toStringOrNull(json['journey_start_date']),
      profitSinceStart:
          _toDouble(json['profit_since_start'] ?? json['total_profit']),
      lossSinceStart: _toDouble(json['loss_since_start'] ?? json['total_loss']),
      netResultSinceStart: _toDouble(
          json['net_result_since_start'] ?? json['net_change_since_start']),
      averageMonthlyProfit: _toDouble(json['average_monthly_profit']),
      netProfitMargin: _toDouble(json['net_profit_margin']),
      expenseRatio: _toDouble(json['expense_ratio']),
      incomeStreams:
          _fromJsonList(json['income_streams'], IncomeStream.fromJson),
      profitEntries:
          _fromJsonList(json['profit_entries'], ProfitEntry.fromJson),
      netWorthHistory:
          _fromJsonList(json['net_worth_history'], NetWorthSnapshot.fromJson),
    );
  }

  final String currency;
  final double monthlyIncome;
  final double monthlyExpenses;
  final double monthlySavings;
  final double savingsRate;
  final double? netWorth;
  final double? netWorthChange;
  final String? journeyStartDate;
  final double profitSinceStart;
  final double lossSinceStart;
  final double netResultSinceStart;
  final double averageMonthlyProfit;
  final double netProfitMargin;
  final double expenseRatio;
  final List<IncomeStream> incomeStreams;
  final List<ProfitEntry> profitEntries;
  final List<NetWorthSnapshot> netWorthHistory;
}

class IncomeStream {
  const IncomeStream({
    required this.id,
    required this.name,
    required this.amount,
    this.frequency = 'monthly',
    this.isActive = true,
  });

  factory IncomeStream.fromJson(Map<String, dynamic> json) => IncomeStream(
        id: _toInt(json['id']),
        name: _toString(json['name']),
        amount: _toDouble(json['amount']),
        frequency: _toString(json['frequency'], fallback: 'monthly'),
        isActive: _toBool(json['is_active'], fallback: true),
      );

  final int id;
  final String name;
  final double amount;
  final String frequency;
  final bool isActive;
}

class ProfitEntry {
  const ProfitEntry({
    required this.id,
    required this.amount,
    required this.date,
    required this.type,
    this.note = '',
  });

  factory ProfitEntry.fromJson(Map<String, dynamic> json) => ProfitEntry(
        id: _toInt(json['id']),
        amount: _toDouble(json['amount']),
        date: _toString(json['date']),
        type: _toString(json['type'], fallback: 'profit'),
        note: _toString(json['note']),
      );

  final int id;
  final double amount;
  final String date;
  final String type;
  final String note;
}

class NetWorthSnapshot {
  const NetWorthSnapshot({
    required this.id,
    required this.amount,
    required this.asOf,
    this.note = '',
  });

  factory NetWorthSnapshot.fromJson(Map<String, dynamic> json) =>
      NetWorthSnapshot(
        id: _toInt(json['id']),
        amount: _toDouble(json['amount']),
        asOf: _toString(json['as_of']),
        note: _toString(json['note']),
      );

  final int id;
  final double amount;
  final String asOf;
  final String note;
}

// ---------------------------------------------------------------------------
// Journal entries ("Posts")
// ---------------------------------------------------------------------------

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.title,
    this.body = '',
    this.mood,
    this.createdAt = '',
    this.updatedAt = '',
    this.image,
    this.authorName = '',
    this.viewCount = 0,
    this.likeCount = 0,
    this.viewed = false,
    this.read = false,
    this.liked = false,
    this.saved = false,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: _toInt(json['id']),
        title: _toString(json['title']),
        body: _toString(json['body']),
        mood: _toStringOrNull(json['mood']),
        createdAt: _toString(json['created_at']),
        updatedAt: _toString(json['updated_at']),
        image: _toStringOrNull(json['image'] ?? json['photo']),
        authorName: _toString(json['author_name'] ?? json['author']),
        viewCount: _toInt(json['view_count']),
        likeCount: _toInt(json['like_count']),
        viewed: _toBool(json['viewed']),
        read: _toBool(json['read']),
        liked: _toBool(json['liked']),
        saved: _toBool(json['saved']),
      );

  final int id;
  final String title;
  final String body;

  /// "great" | "good" | "neutral" | "low" | null.
  final String? mood;
  final String createdAt;
  final String updatedAt;
  final String? image;
  final String authorName;
  final int viewCount;
  final int likeCount;
  final bool viewed;
  final bool read;
  final bool liked;
  final bool saved;

  JournalEntry copyWith({
    int? viewCount,
    int? likeCount,
    bool? viewed,
    bool? read,
    bool? liked,
    bool? saved,
  }) =>
      JournalEntry(
        id: id,
        title: title,
        body: body,
        mood: mood,
        createdAt: createdAt,
        updatedAt: updatedAt,
        image: image,
        authorName: authorName,
        viewCount: viewCount ?? this.viewCount,
        likeCount: likeCount ?? this.likeCount,
        viewed: viewed ?? this.viewed,
        read: read ?? this.read,
        liked: liked ?? this.liked,
        saved: saved ?? this.saved,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'mood': mood,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

// ---------------------------------------------------------------------------
// Memories / Achievements
// ---------------------------------------------------------------------------

class Memory {
  const Memory({
    required this.id,
    required this.title,
    this.description = '',
    this.date = '',
    this.photo,
    this.createdAt = '',
  });

  factory Memory.fromJson(Map<String, dynamic> json) => Memory(
        id: _toInt(json['id']),
        title: _toString(json['title']),
        description: _toString(json['description']),
        date: _toString(json['date']),
        photo: _toStringOrNull(json['photo']),
        createdAt: _toString(json['created_at']),
      );

  final int id;
  final String title;
  final String description;
  final String date;

  /// Absolute image URL, or null when no photo was uploaded.
  final String? photo;
  final String createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'date': date,
        'photo': photo,
        'created_at': createdAt,
      };
}

// ---------------------------------------------------------------------------
// Reminders
// ---------------------------------------------------------------------------

class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    this.message = '',
    required this.time,
    this.days = const <int>[],
    this.category = 'health',
    this.isActive = true,
    this.createdAt = '',
  });

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: _toInt(json['id']),
        title: _toString(json['title']),
        message: _toString(json['message']),
        time: _toString(json['time']),
        days: _toIntList(json['days']),
        category: _toString(json['category'], fallback: 'health'),
        isActive: _toBool(json['is_active'], fallback: true),
        createdAt: _toString(json['created_at']),
      );

  final int id;
  final String title;
  final String message;

  /// Local time as "HH:MM".
  final String time;

  /// Weekday indices 0..6 with Monday = 0; empty means every day.
  final List<int> days;
  final String category;
  final bool isActive;
  final String createdAt;

  bool get isDaily => days.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'message': message,
        'time': time,
        'days': days,
        'category': category,
        'is_active': isActive,
        'created_at': createdAt,
      };
}

/// Compatibility aliases.
typedef MemoryItem = Memory;
typedef UserProfile = User;

/// One pushed Signo event, from GET /notifications/.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    this.body = '',
    this.kind = 'general',
    this.createdAt = '',
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: _toInt(json['id']),
        title: _toString(json['title']),
        body: _toString(json['body']),
        kind: _toString(json['kind'], fallback: 'general'),
        createdAt: _toString(json['created_at']),
        readAt: _toStringOrNull(json['read_at']),
      );

  final int id;
  final String title;
  final String body;
  final String kind;
  final String createdAt;
  final String? readAt;

  bool get isUnread => readAt == null || readAt!.isEmpty;

  IconData get icon {
    switch (kind) {
      case 'reminder':
        return Icons.alarm_rounded;
      case 'streak_milestone':
        return Icons.local_fire_department_rounded;
      case 'goal_achieved':
        return Icons.verified_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}
