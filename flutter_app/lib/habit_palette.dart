/// Shared habit icon + color vocabulary.
///
/// One canonical icon-name list used by BOTH the create/edit picker and
/// every renderer (Today checklist, Habits page, widgets sync) — the app
/// previously had two divergent copies and users could not pick icons
/// at all (they were derived from category).
library;

import 'package:flutter/material.dart';

/// Backend-legal color keys (habits/models.py COLORS) with display tones.
const Map<String, Color> habitColorTones = <String, Color>{
  'primary': Color(0xFFFFC174), // amber
  'secondary': Color(0xFF6BD8CB), // teal
  'tertiary': Color(0xFFC7C8FF), // indigo
  'error': Color(0xFFFFB4AB), // coral
};

const List<String> habitColorKeys = <String>[
  'primary', 'secondary', 'tertiary', 'error',
];

/// Every icon a user can choose, as (backendKey, emoji-ish preview, widget).
const List<(String, IconData)> habitIconChoices = <(String, IconData)>[
  ('bolt', Icons.bolt_outlined),
  ('menu_book', Icons.menu_book_outlined),
  ('fitness_center', Icons.fitness_center),
  ('directions_run', Icons.directions_run),
  ('sports_gymnastics', Icons.sports_gymnastics),
  ('water_drop', Icons.water_drop_outlined),
  ('restaurant', Icons.restaurant_outlined),
  ('self_improvement', Icons.self_improvement),
  ('spa', Icons.spa_outlined),
  ('psychology', Icons.psychology_outlined),
  ('bedtime', Icons.bedtime_outlined),
  ('savings', Icons.savings_outlined),
  ('account_balance', Icons.account_balance_outlined),
  ('paid', Icons.paid_outlined),
  ('trending_up', Icons.trending_up_outlined),
  ('edit', Icons.edit_note_outlined),
  ('code', Icons.code_outlined),
  ('language', Icons.language_outlined),
  ('music_note', Icons.music_note_outlined),
  ('camera_alt', Icons.camera_alt_outlined),
  ('brush', Icons.brush_outlined),
  ('timer', Icons.timer_outlined),
  ('wb_sunny', Icons.wb_sunny_outlined),
  ('favorite', Icons.favorite_outline),
  ('star', Icons.star_outline),
  ('emoji_events', Icons.emoji_events_outlined),
  ('school', Icons.school_outlined),
  ('work', Icons.work_outline),
  ('cleaning_services', Icons.cleaning_services_outlined),
  ('pets', Icons.pets),
  ('nature', Icons.nature_people_outlined),
  ('volunteer_activism', Icons.volunteer_activism_outlined),
  ('prayer', Icons.follow_the_signs_outlined),
];

/// Resolve any stored icon key to a widget; unknown keys fall back to bolt.
IconData habitIcon(String? name) {
  for (final (key, icon) in habitIconChoices) {
    if (key == name) return icon;
  }
  // Historical aliases from the old duplicated maps.
  switch (name) {
    case 'book':
    case 'journal':
      return Icons.menu_book_outlined;
    case 'run':
      return Icons.directions_run;
    case 'schedule':
      return Icons.timer_outlined;
    case null:
    case '':
      return Icons.bolt_outlined;
  }
  return Icons.bolt_outlined;
}

/// The color key users most likely want for a category (used as the
/// picker's initial selection).
String defaultColorForCategory(String category) {
  switch (category) {
    case 'physical':
      return 'error';
    case 'financial':
      return 'tertiary';
    case 'spiritual':
      return 'primary';
    case 'mental':
    default:
      return 'secondary';
  }
}
