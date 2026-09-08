import 'package:flutter/material.dart';

import '../api.dart';
import '../habit_palette.dart';
import '../models.dart';
import '../refresh_bus.dart';
import '../widgets/mura_widgets.dart';
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
      final map = await _fetchRecentMap(habits.map((h) => h.id).toList());
      if (!mounted) return;
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

  /// GET /habits/history_batch/ - ONE call for every habit's history,
  /// normalized to exactly 7 trailing slots (true / false / null, oldest
  /// first) per habit id. Habits missing from the batch are simply absent
  /// (the dots render as "no data" like before).
  Future<Map<int, List<bool?>>> _fetchRecentMap(List<int> habitIds) async {
    try {
      final batch = await _api.habitHistoryBatch(days: 10);
      final map = <int, List<bool?>>{};
      for (final id in habitIds) {
        final hist = batch.histories[id];
        if (hist == null) continue;
        final flags = hist.days.map<bool?>((d) => d.completed).toList();
        if (flags.length >= 7) {
          map[id] = flags.sublist(flags.length - 7);
        } else {
          map[id] = <bool?>[
            ...List<bool?>.filled(7 - flags.length, null),
            ...flags,
          ];
        }
      }
      return map;
    } catch (_) {
      // Dots degrade to "no data" when the batch feed is unavailable.
      return <int, List<bool?>>{};
    }
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

  Color _colorOf(String? key) => habitColorTones[key] ?? _pal.amber;

  IconData _iconFor(String? name) => habitIcon(name);

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
        // ListView.builder: only visible rows build, so 100+ habits scroll
        // exactly as smoothly as 5 (the old eager list built every card).
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
          // header, stats, gap, habit rows (or empty state), create, heatmap
          itemCount: 3 + (_habits.isEmpty ? 1 : _habits.length) + 2,
          itemBuilder: (context, index) {
            if (index == 0) return _buildHeader();
            if (index == 1) {
              return Padding(
                padding: const EdgeInsets.only(top: 18),
                child: _buildStatsRow(),
              );
            }
            if (index == 2) return const SizedBox(height: 18);
            final habitIndex = index - 3;
            if (_habits.isEmpty && habitIndex == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildEmptyHabitsCard(),
              );
            }
            if (habitIndex < _habits.length) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildHabitCard(_habits[habitIndex]),
              );
            }
            final tail = habitIndex - (_habits.isEmpty ? 1 : _habits.length);
            if (tail == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: _buildCreateHabitButton(),
              );
            }
            return _buildHeatmapCard();
          },
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
        onPressed: () => _showHabitEditor(),
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

  Widget _buildEmptyHabitsCard() {
    return Container(
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
          const SizedBox(height: 10),
          Text(
            'No habits yet - tap + to forge your first one.',
            style: TextStyle(color: _pal.textDim, fontSize: 13.5),
          ),
        ],
      ),
    );
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
      onPressed: () => _showHabitEditor(),
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

    return InkWell(
      // Interactivity: the whole card opens the editor (icon, color,
      // name, schedule, delete) — previously nothing on this page was
      // tappable.
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showHabitEditor(h),
      child: Container(
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

  // -------------------------------------------------------- habit editor

  /// Create (habit == null) or edit an existing habit: name, icon picker,
  /// color picker, category, schedule, grace days — plus delete when
  /// editing. The backend accepts icon/color on both POST and PATCH.
  Future<void> _showHabitEditor([Habit? habit]) async {
    var name = habit?.name ?? '';
    var category = habit?.category ?? 'mental';
    var icon = habit?.icon ?? 'bolt';
    var color = habit?.color ?? defaultColorForCategory(category);
    var grace = habit?.graceDaysPerWeek ?? 1;
    var scheduleDays =
        habit?.scheduleDays ?? const <int>[1, 2, 3, 4, 5, 6, 7];
    var busy = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final nav = Navigator.of(dialogContext);
            final editing = habit != null;

            Future<void> submit() async {
              if (name.trim().isEmpty || busy) return;
              setDialogState(() {
                busy = true;
                error = null;
              });
              try {
                final fields = <String, dynamic>{
                  'name': name.trim(),
                  'category': category,
                  'icon': icon,
                  'color': color,
                  'grace_days_per_week': grace,
                  'schedule_days': scheduleDays,
                };
                if (editing) {
                  await _api.updateHabit(habit.id, fields);
                  nav.pop();
                  if (!mounted) return;
                  _load();
                  _toast('Habit updated.');
                } else {
                  await _api.createHabit(
                    name: name.trim(),
                    category: category,
                    icon: icon,
                    color: color,
                    graceDaysPerWeek: grace,
                    scheduleDays: scheduleDays,
                  );
                  nav.pop();
                  if (!mounted) return;
                  _load();
                  _toast('Habit created.');
                }
              } catch (_) {
                setDialogState(() {
                  busy = false;
                  error = 'Could not save the habit. Please try again.';
                });
              }
            }

            Future<void> delete() async {
              final ok = await showDialog<bool>(
                context: dialogContext,
                builder: (ctx) => AlertDialog(
                  backgroundColor: _pal.card,
                  title: Text('Delete "${habit!.name}"?',
                      style:
                          TextStyle(color: _pal.text, fontSize: 16)),
                  content: Text(
                      'Its history and streaks are removed permanently.',
                      style:
                          TextStyle(color: _pal.textDim, fontSize: 12.5)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancel',
                            style: TextStyle(color: _pal.textDim))),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Delete',
                            style: TextStyle(
                                color: _pal.coral,
                                fontWeight: FontWeight.w700))),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await _api.deleteHabit(habit!.id);
                nav.pop();
                if (!mounted) return;
                _load();
                _toast('Habit deleted.');
              } catch (_) {
                setDialogState(() {
                  error = 'Could not delete the habit.';
                });
              }
            }

            return AlertDialog(
              backgroundColor: _pal.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                editing ? 'Edit Habit' : 'New Habit',
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
                      autofocus: !editing,
                      controller: TextEditingController(text: name)
                        ..selection = TextSelection.collapsed(
                            offset: name.length),
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
                      'ICON',
                      style: TextStyle(
                        color: _pal.textDim,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Icon picker: a lazy grid of every habitIconChoices
                    // entry; the selected one glows amber.
                    SizedBox(
                      height: 210,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        itemCount: habitIconChoices.length,
                        itemBuilder: (context, i) {
                          final (key, iconData) = habitIconChoices[i];
                          final selected = key == icon;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setDialogState(() => icon = key),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? _pal.amber
                                    : _pal.cardAlt,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? _pal.amber
                                      : _pal.outline,
                                ),
                              ),
                              child: Icon(
                                iconData,
                                size: 20,
                                color: selected
                                    ? _pal.onAmber
                                    : _colorOf(color),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'COLOR',
                      style: TextStyle(
                        color: _pal.textDim,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: habitColorKeys.map((key) {
                        final selected = key == color;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => setDialogState(() => color = key),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _colorOf(key),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? _pal.text
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: selected
                                  ? Icon(Icons.check,
                                      size: 16, color: _pal.bg)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
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
                          (sel) => setDialogState(() {
                            category = c;
                            // Sensible color default follows category
                            // until the user has chosen one themselves.
                            color = defaultColorForCategory(c);
                          }),
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
                if (editing)
                  TextButton(
                    onPressed: busy ? null : delete,
                    style: TextButton.styleFrom(
                      foregroundColor: _pal.coral,
                    ),
                    child: const Text(
                      'DELETE',
                      style: TextStyle(fontSize: 12.5, letterSpacing: 1),
                    ),
                  ),
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
                      : Text(
                          editing ? 'SAVE' : 'CREATE',
                          style: const TextStyle(
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
  Widget build(BuildContext context) {
    // Skeleton preview of the real layout: stats pair, then habit-card
    // blocks — so the first paint already looks like the finished page.
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
      children: [
        for (final _ in Iterable<int>.generate(3))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Shimmer(width: 200, height: 18),
              const SizedBox(height: 8),
              Shimmer(width: 120, height: 12),
              const SizedBox(height: 10),
            ],
          ),
        Row(
          children: [
            Expanded(child: Shimmer(height: 76, radius: 16)),
            const SizedBox(width: 12),
            Expanded(child: Shimmer(height: 76, radius: 16)),
          ],
        ),
        const SizedBox(height: 18),
        for (final _ in Iterable<int>.generate(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Shimmer(height: 110, radius: 16),
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
  Widget build(BuildContext context) {
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
