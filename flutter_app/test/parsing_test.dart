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
}
