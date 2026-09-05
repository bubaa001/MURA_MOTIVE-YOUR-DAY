import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../refresh_bus.dart';
import '../theme.dart'; // ignore: unused_import

/// MURA - Habits screen: active habit cards (icon, color dot, streaks,
/// 7-day mini history), a GitHub-style consistency heatmap (weeks x 7
/// rounded cells shaded by level 0..4), and a FAB that opens the
/// create-habit dialog (name / category / grace days).
///
/// All ApiClient calls (habits / habitHistory / heatmap / createHabit)
/// resolve statically against api.dart's singleton [ApiClient.instance].
class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> with AppRefreshListener {
  MuraPalette get _pal => MuraPalette.of(context);
  final _api = ApiClient.instance;

  bool _loading = true;
  String? _error;

  List<Habit> _habits = const <Habit>[];

  /// One column of exactly 7 heatmap cells per week (level 0..4).
  List<List<HeatmapCell>> _levels = const <List<HeatmapCell>>[];

  /// habitId -> last 7 days (oldest first; true/false/null).
  Map<int, List<bool?>> _recent = <int, List<bool?>>{};

  // Obsidian & Amber palette (kept local so this page compiles standalone).

  static const List<Color> _heatScale = [
    Color(0xFF231B11),
    Color(0xFF503512),
    Color(0xFF8A5D1C),
    Color(0xFFC98A2E),
    Color(0xFFFFC174),
  ];

  static const List<String> _categories = [
    'physical',
    'mental',
    'financial',
    'spiritual',
  ];

  static const Map<String, Color> _categoryColors = {
    'primary': Color(0xFFFFC174),
    'secondary': Color(0xFF6BD8CB),
    'tertiary': Color(0xFFC7C8FF),
    'error': Color(0xFFFFB4AB),
    'physical': Color(0xFFFF8A80),
    'mental': Color(0xFF6BD8CB),
    'financial': Color(0xFFC7C8FF),
    'spiritual': Color(0xFFFFC174),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  // ---------------------------------------------------------------- data

  @override
  void onAppRefresh() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final habits = await _fetchHabits();
      if (!mounted) return;
      setState(() => _habits = habits);

      final levels = await _fetchHeatmapLevels();
      final recents = await Future.wait<List<bool?>?>(
        habits.map((h) => _fetchRecent(h.id)).toList(),
      );
      if (!mounted) return;
      final map = <int, List<bool?>>{};
      for (var i = 0; i < habits.length && i < recents.length; i++) {
        final r = recents[i];
        if (r != null) map[habits[i].id] = r;
      }
      setState(() {
        _levels = levels;
        _recent = map;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load habits.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// GET /habits/ - active habits with computed streaks.
  Future<List<Habit>> _fetchHabits() => _api.habits();

  /// GET /habits/heatmap_data/, normalized to exactly 7 cells per week.
  Future<List<List<HeatmapCell>>> _fetchHeatmapLevels() async {
    final HeatmapData data = await _api.heatmap();
    return data.weeks.map((HeatmapWeek week) {
      final row = <HeatmapCell>[];
      for (var i = 0; i < 7; i++) {
        if (i < week.days.length) {
          row.add(week.days[i]);
        } else {
          row.add(const HeatmapCell(date: ''));
        }
      }
      return row;
    }).toList(growable: false);
  }

  /// GET /habits/{id}/history/ - exactly 7 trailing slots
  /// (true / false / null, oldest first), or null when unavailable.
  Future<List<bool?>?> _fetchRecent(int habitId) async {
    try {
      final hist = await _api.habitHistory(habitId, days: 10);
      final flags = hist.days.map<bool?>((d) => d.completed).toList();
      if (flags.length >= 7) return flags.sublist(flags.length - 7);
      return <bool?>[
        ...List<bool?>.filled(7 - flags.length, null),
        ...flags,
      ];
    } catch (_) {
      return null;
    }
  }

  /// POST /habits/.
  Future<Habit> _createHabit(
      String name, String category, int graceDaysPerWeek) {
    return _api.createHabit(
      name: name,
      category: category,
      graceDaysPerWeek: graceDaysPerWeek,
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(color: _pal.text)),
        backgroundColor: _pal.cardAlt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // -------------------------------------------------------------- helpers

  Color _colorOf(String? key) => _categoryColors[key] ?? _pal.amber;

  IconData _iconFor(String? name) {
    switch (name) {
      case 'menu_book':
      case 'book':
        return Icons.menu_book_outlined;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'directions_run':
      case 'run':
        return Icons.directions_run;
      case 'savings':
        return Icons.savings_outlined;
      case 'paid':
      case 'account_balance':
        return Icons.account_balance_outlined;
      case 'self_improvement':
        return Icons.self_improvement;
      case 'spa':
        return Icons.spa_outlined;
      case 'psychology':
        return Icons.psychology_outlined;
      case 'bedtime':
        return Icons.bedtime_outlined;
      case 'water_drop':
        return Icons.water_drop_outlined;
      case 'restaurant':
        return Icons.restaurant_outlined;
      case 'edit':
      case 'journal':
        return Icons.edit_note_outlined;
      case 'code':
        return Icons.code_outlined;
      case 'language':
        return Icons.language_outlined;
      case 'music_note':
        return Icons.music_note_outlined;
      case 'timer':
      case 'schedule':
        return Icons.timer_outlined;
      case 'bolt':
        return Icons.bolt_outlined;
      case 'star':
        return Icons.star_outline;
      default:
        return Icons.bolt_outlined;
    }
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading && _habits.isEmpty && _error == null) {
      body = const Center(child: _LoadingView());
    } else if (_error != null && _habits.isEmpty) {
      body = _ErrorState(message: _error!, onRetry: () => _load());
    } else {
      body = RefreshIndicator(
        color: _pal.amber,
        backgroundColor: const Color(0xFF1C1610),
        onRefresh: () async => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            _buildStatsRow(),
            const SizedBox(height: 18),
            ..._buildHabitCards(),
            const SizedBox(height: 14),
            _buildCreateHabitButton(),
            const SizedBox(height: 28),
            _buildHeatmapCard(),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Theme.of(context).colorScheme.surface
          : _pal.bg,
      body: SafeArea(child: body),
      floatingActionButton: FloatingActionButton(
        heroTag: 'habits-fab',
        onPressed: _showCreateDialog,
        backgroundColor: _pal.amberDeep,
        foregroundColor: _pal.onAmber,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, size: 26),
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department, color: scheme.primary, size: 15),
            SizedBox(width: 6),
            Text(
              'MURA',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${_habits.length} active \u00b7 protect the streak',
          style: TextStyle(
            color: light ? scheme.onSurfaceVariant : _pal.textDim,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildHabitCards() {
    if (_habits.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? Theme.of(context).colorScheme.surfaceContainer
                : _pal.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: Column(
            children: [
              Icon(Icons.add_circle_outline, color: _pal.textDim, size: 30),
              SizedBox(height: 10),
              Text(
                'No habits yet - tap + to forge your first one.',
                style: TextStyle(color: _pal.textDim, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ];
    }

    final cards = <Widget>[];
    for (var i = 0; i < _habits.length; i++) {
      cards.add(_buildHabitCard(_habits[i]));
      if (i < _habits.length - 1) cards.add(const SizedBox(height: 12));
    }
    return cards;
  }

  Widget _buildStatsRow() {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final activeStreaks =
        _habits.where((habit) => habit.currentStreak > 0).length;
    var completed = 0;
    var recorded = 0;
    for (final days in _recent.values) {
      for (final day in days) {
        if (day == null) continue;
        recorded++;
        if (day) completed++;
      }
    }
    final completion = recorded == 0 ? 0 : (completed / recorded * 100).round();

    Widget stat(String label, String value, Color accent, IconData? icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: light ? scheme.surfaceContainer : _pal.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: light
                  ? scheme.outlineVariant.withAlpha(90)
                  : const Color(0x12FFFFFF),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: light ? scheme.onSurfaceVariant : _pal.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: accent,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 5),
                    Icon(icon, color: accent, size: 18),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        stat(
          'ACTIVE STREAKS',
          '$activeStreaks',
          _pal.amberDeep,
          Icons.local_fire_department,
        ),
        const SizedBox(width: 12),
        stat(
          'COMPLETION',
          '$completion%',
          light ? Color(0xFF0D9488) : _pal.amberDeep,
          null,
        ),
      ],
    );
  }

  Widget _buildCreateHabitButton() {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return OutlinedButton.icon(
      onPressed: _showCreateDialog,
      icon: const Icon(Icons.add_circle_outline, size: 20),
      label: const Text('Create New Habit'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: light ? scheme.onSurfaceVariant : _pal.textDim,
        side: BorderSide(
          color: light ? scheme.outlineVariant : _pal.outline,
          style: BorderStyle.solid,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildHabitCard(Habit h) {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final accent = _colorOf(h.color);
    final grace = h.graceDaysPerWeek;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: light ? scheme.surfaceContainer : _pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: light
                ? scheme.outlineVariant.withAlpha(90)
                : const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: light ? scheme.surfaceContainerHigh : _pal.cardAlt,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(_iconFor(h.icon), size: 21, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              color: accent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          h.category.toUpperCase(),
                          style: TextStyle(
                            color: light ? scheme.onSurfaceVariant : _pal.textDim,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_fire_department,
                          size: 15, color: _pal.amberDeep),
                      const SizedBox(width: 4),
                      Text(
                        '${h.currentStreak}',
                        style: TextStyle(
                          color: _pal.amber,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'best ${h.bestStreak}',
                    style: TextStyle(
                      color: light ? scheme.onSurfaceVariant : _pal.textDim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSevenDots(h.id)),
              if (grace > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _pal.outline),
                  ),
                  child: Text(
                    '$grace grace/wk',
                    style: TextStyle(
                      color: _pal.textDim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _scheduleLabel(h.scheduleDays),
            style: TextStyle(
              color: light ? scheme.onSurfaceVariant : _pal.textDim,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSevenDots(int habitId) {
    final data = _recent[habitId];
    final dots = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final val = data == null || i >= data.length ? null : data[i];
      final Color c;
      if (val == true) {
        c = _pal.amberDeep;
      } else if (val == false) {
        c = const Color(0xFF2E251A);
      } else {
        c = _pal.cardAlt;
      }

      dots.add(Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ));
    }
    return Row(children: dots);
  }

  String _scheduleLabel(List<int> days) {
    const labels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final normalized = days.where((day) => day >= 1 && day <= 7).toSet();
    if (normalized.length == 7 || normalized.isEmpty) return 'Every day';
    final ordered = normalized.toList()..sort();
    return ordered.map((day) => labels[day - 1]).join(' · ');
  }

  Widget _buildHeatmapCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Theme.of(context).colorScheme.surfaceContainer
            : _pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CONSISTENCY',
                style: TextStyle(
                  color: _pal.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              Text(
                '${_levels.length}w',
                style: TextStyle(
                  color: _pal.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_levels.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No activity recorded yet.',
                style: TextStyle(color: _pal.textDim, fontSize: 13),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _levels.map((week) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: week.map(_heatCell).toList(),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Less',
                style: TextStyle(color: _pal.textDim, fontSize: 10),
              ),
              const SizedBox(width: 6),
              for (var lv = 0; lv <= 4; lv++)
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: _heatScale[lv],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 2),
              Text(
                'More',
                style: TextStyle(color: _pal.textDim, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heatCell(HeatmapCell cell) {
    final int level = cell.level;
    final idx = level < 0 ? 0 : (level > 4 ? 4 : level);
    final Widget square = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: _heatScale[idx],
        borderRadius: BorderRadius.circular(4),
      ),
    );
    final padding = const EdgeInsets.only(right: 3, bottom: 3);
    if (cell.date.isEmpty) {
      return Padding(padding: padding, child: square);
    }
    return Tooltip(
      message: "${cell.date} \u00b7 ${(cell.ratio * 100).round()}% done",
      child: Padding(padding: padding, child: square),
    );
  }

  // -------------------------------------------------------- create dialog

  Future<void> _showCreateDialog() async {
    var name = '';
    var category = 'mental';
    var grace = 1;
    var scheduleDays = <int>[1, 2, 3, 4, 5, 6, 7];
    var busy = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final nav = Navigator.of(dialogContext);

            Future<void> submit() async {
              if (name.trim().isEmpty || busy) return;
              setDialogState(() {
                busy = true;
                error = null;
              });
              try {
                await _api.createHabit(
                  name: name.trim(),
                  category: category,
                  graceDaysPerWeek: grace,
                  scheduleDays: scheduleDays,
                );
                nav.pop();
                if (!mounted) return;
                _load();
                _toast('Habit created.');
              } catch (_) {
                setDialogState(() {
                  busy = false;
                  error = 'Could not create the habit. Please try again.';
                });
              }
            }

            return AlertDialog(
              backgroundColor: _pal.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'New Habit',
                style: TextStyle(
                  color: _pal.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SingleChildScrollView(
                // Keeps the dialog usable when the keyboard squeezes it.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (v) => name = v,
                      style: TextStyle(color: _pal.text, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'e.g. Read 10 pages',
                        hintStyle: const TextStyle(color: Color(0xFF6E6052)),
                        filled: true,
                        fillColor: _pal.cardAlt,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _pal.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: _pal.amberDeep, width: 1.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'CATEGORY',
                      style: TextStyle(
                        color: _pal.textDim,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categories.map((c) {
                        return _buildCategoryChip(
                          c,
                          c == category,
                          (sel) => setDialogState(() => category = c),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SCHEDULE',
                      style: TextStyle(
                        color: _pal.textDim,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(7, (index) {
                        final day = index + 1;
                        const labels = <String>[
                          'M',
                          'T',
                          'W',
                          'T',
                          'F',
                          'S',
                          'S',
                        ];
                        final selected = scheduleDays.contains(day);
                        return FilterChip(
                          label: Text(labels[index]),
                          selected: selected,
                          onSelected: (value) {
                            setDialogState(() {
                              if (value) {
                                scheduleDays = [...scheduleDays, day]..sort();
                              } else if (scheduleDays.length > 1) {
                                scheduleDays = scheduleDays
                                    .where((item) => item != day)
                                    .toList();
                              }
                            });
                          },
                          selectedColor: _pal.amberDeep,
                          backgroundColor: _pal.cardAlt,
                          labelStyle: TextStyle(
                            color: selected ? _pal.onAmber : _pal.textDim,
                            fontWeight: FontWeight.w700,
                          ),
                          side: BorderSide(color: _pal.outline),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Grace days / week',
                            style: TextStyle(color: _pal.textDim, fontSize: 13.5),
                          ),
                        ),
                        IconButton(
                          onPressed: grace > 0
                              ? () => setDialogState(() => grace--)
                              : null,
                          icon: Icon(Icons.remove_circle_outline,
                              color: _pal.amber, size: 22),
                          splashRadius: 20,
                        ),
                        SizedBox(
                          width: 26,
                          child: Text(
                            '$grace',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _pal.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: grace < 3
                              ? () => setDialogState(() => grace++)
                              : null,
                          icon: Icon(Icons.add_circle_outline,
                              color: _pal.amber, size: 22),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFFFFB4AB),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => nav.pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: _pal.textDim,
                  ),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(fontSize: 12.5, letterSpacing: 1),
                  ),
                ),
                ElevatedButton(
                  onPressed: (name.trim().isEmpty || busy) ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pal.amberDeep,
                    foregroundColor: _pal.onAmber,
                    disabledBackgroundColor: const Color(0xFF54430F),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: busy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _pal.onAmber,
                          ),
                        )
                      : const Text(
                          'CREATE',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryChip(
      String value, bool selected, ValueChanged<bool> onSelected) {
    final dot = _colorOf(value);
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            value[0].toUpperCase() + value.substring(1),
            style: TextStyle(
              color: selected ? _pal.amber : _pal.textDim,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: const Color(0x40FFC174),
      backgroundColor: _pal.cardAlt,
      side: BorderSide(
        color: selected ? _pal.amber : _pal.outline,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );
  }
}

// ------------------------------------------------------------ shared bits

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        CircularProgressIndicator(color: Color(0xFFF59E0B), strokeWidth: 2.6),
        SizedBox(height: 16),
        Text(
          'Loading habits...',
          style: TextStyle(color: Color(0xFFA08E7A), fontSize: 13),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFF241B12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_off_rounded,
                color: Color(0xFFA08E7A), size: 28),
          ),
          const SizedBox(height: 18),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFA08E7A),
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFC174),
              side: const BorderSide(color: Color(0xFFF59E0B)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
