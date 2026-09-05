/// Pushes fresh home-screen widget data to the native side once the Today
/// screen has real content (quote, insight, today's habits, best streak).
library;

import 'package:flutter/services.dart';

const MethodChannel _widgetsChannel = MethodChannel('com.bubaa.mura/widgets');

Future<void> syncHomeWidgets({
  String? quote,
  String? quoteSource,
  String? insight,
  String? insightSource,
  List<String> habitNames = const <String>[],
  List<bool> habitStates = const <bool>[],
  int? streak,
}) async {
  try {
    await _widgetsChannel.invokeMethod<void>('update', <String, Object?>{
      'quote': quote ?? '',
      'quote_source': quoteSource ?? '',
      'insight': insight ?? '',
      'insight_source': insightSource ?? '',
      'habits_names': habitNames,
      'habits_states': habitStates.map((bool done) => done ? '1' : '0').toList(),
      'streak': streak == null ? '' : streak.toString(),
      'streak_label': 'DAY STREAK',
    });
  } catch (_) {
    // Widget sync is best-effort; never break the page for it.
  }
}
