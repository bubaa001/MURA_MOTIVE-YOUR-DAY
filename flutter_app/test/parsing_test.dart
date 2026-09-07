import 'package:flutter_test/flutter_test.dart';

import 'package:mura/models.dart';

void main() {
  test('parses /content/daily/ payload', () {
    const raw = <String, dynamic>{
      'date': '2026-08-26',
      'quote': {
        'id': 7,
        'type': 'quote',
        'text': 'Strength and growth.',
        'source': 'Think and Grow Rich',
        'tags': ['effort', 'discipline'],
        'created_at': '2026-08-25T16:27:11.499264Z',
      },
      'prayer': {
        'id': 18,
        'type': 'prayer',
        'text': 'Whatsoever ye desire.',
        'source': 'Mark 11:24 (KJV)',
        'tags': ['prayer', 'abundance', 'scripture'],
        'created_at': '2026-08-25T16:27:11.565144Z',
      },
      'philosophy': null,
    };
    final DailyContent c = DailyContent.fromJson(raw);
    expect(c.quote!.tags, <String>['effort', 'discipline']);
  });

  test('parses /habits/today/ payload', () {
    const raw = <String, dynamic>{
      'date': '2026-08-26',
      'items': [
        {
          'habit_id': 1,
          'name': 'Drink Water',
          'icon': 'water_drop',
          'color': 'error',
          'category': 'physical',
          'completed': false,
          'log_id': 5,
        },
      ],
    };
    final TodayChecklist t = TodayChecklist.fromJson(raw);
    expect(t.items.single.name, 'Drink Water');
  });

  test('parses /me/ plan and push_topic with defaults', () {
    const raw = <String, dynamic>{
      'id': 1,
      'username': 'disciplined',
      'email': 'me@example.com',
      'plan': 'premium',
      'push_topic': 'mura-user-1',
    };
    final User u = User.fromJson(raw);
    expect(u.plan, 'premium');
    expect(u.pushTopic, 'mura-user-1');

    // Old payloads without the new fields fall back to "free" / ''.
    final User legacy = User.fromJson(const <String, dynamic>{
      'id': 2,
      'username': 'legacy',
    });
    expect(legacy.plan, 'free');
    expect(legacy.pushTopic, '');
  });

  test('parses /habits/history_batch/ payload keyed by habit id', () {
    const raw = <String, dynamic>{
      'days_span': 180,
      'habits': {
        '3': {
          'days': [
            {'date': '2026-09-01', 'completed': true},
            {'date': '2026-09-02', 'completed': false},
          ],
          'streaks': {'current': 3, 'best': 12},
        },
        '17': {
          'days': [
            {'date': '2026-09-01', 'completed': true},
          ],
          'streaks': {'current': 1, 'best': 1},
        },
      },
    };
    final HabitHistoryBatch b = HabitHistoryBatch.fromJson(raw);
    expect(b.daysSpan, 180);
    expect(b.histories.keys, unorderedEquals(<int>[3, 17]));
    expect(b.histories[3]!.currentStreak, 3);
    expect(b.histories[3]!.bestStreak, 12);
    expect(b.histories[3]!.days.first.completed, isTrue);
    expect(b.histories[17]!.days.single.date, '2026-09-01');

    // Missing habits map or malformed ids degrade to an empty batch.
    final HabitHistoryBatch empty =
        HabitHistoryBatch.fromJson(const <String, dynamic>{'days_span': 7});
    expect(empty.histories, isEmpty);
  });
}
