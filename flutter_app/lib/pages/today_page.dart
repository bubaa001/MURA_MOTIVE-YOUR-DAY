import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api.dart';
import '../home_widgets.dart';
import '../models.dart';
import '../refresh_bus.dart';
import '../theme.dart'; // ignore: unused_import

/// MURA - Today screen: greeting, tap-to-reveal daily quote, habit
/// checklist with animated circular checkboxes + streak chips, and
/// pull-to-refresh. Dark Obsidian & Amber styling.
///
/// Core ApiClient calls: dailyContent(), todayChecklist(), toggleHabit(),
/// plus an optional habits() enrichment for the initial streak chips. All
/// resolve statically against api.dart's singleton [ApiClient.instance].
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with AppRefreshListener {
  MuraPalette get _pal => MuraPalette.of(context);
  final _api = ApiClient.instance;

  bool _loading = true;
  String? _error;
  bool _revealed = false;
  bool _motionPaused = false;

  DailyContent? _content;
  List<ContentItem> _motionQuotes = const <ContentItem>[];
  List<TodayItem> _items = const <TodayItem>[];
  final Map<int, bool> _doneOverride = <int, bool>{};
  final Map<int, int> _streaks = <int, int>{};
  final Set<int> _busyIds = <int>{};
  final PageController _motionController = PageController();
  Timer? _motionTimer;
  int _motionIndex = 0;

  // Obsidian & Amber palette (kept local so this page compiles standalone).

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _startMotionTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _motionTimer?.cancel();
    _motionController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data

  @override
  void onAppRefresh() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    // Load each source independently so a slow or failed feed never blanks
    // the whole Today screen — whatever succeeds still shows.
    final List<String> failures = <String>[];
    DailyContent? content;
    TodayChecklist? checklist;
    List<ContentItem> motionQuotes = const <ContentItem>[];

    try {
      content = await _api.dailyContent();
    } catch (e) {
      failures.add(friendlyError(e));
    }
    try {
      checklist = await _api.todayChecklist();
    } catch (e) {
      failures.add(friendlyError(e));
    }
    try {
      motionQuotes = await _api.motionQuotes();
    } catch (e) {
      failures.add(friendlyError(e));
    }

    if (!mounted) return;
    final int? dailyQuoteId = content?.quote?.id;
    final List<ContentItem> filtered = motionQuotes
        .where((ContentItem item) => item.id != dailyQuoteId)
        .toList(growable: false);
    setState(() {
      _content = content;
      _motionQuotes = filtered;
      _items = checklist?.items ?? const <TodayItem>[];
      _error = failures.isEmpty ? null : 'Could not load today: ' + failures.first;
      _doneOverride.clear();
    });
    _restartMotionTimer();
    if (filtered.isNotEmpty) {
      // Widget sync is best-effort and must never break the page.
      try {
        await _api.updateMotionQuoteWidget(filtered);
      } catch (_) {}
    }
    await _enrichStreaks();
    _syncWidgets();
    if (!silent && mounted) setState(() => _loading = false);
  }

  /// Push whatever loaded to the home-screen widgets (quote, insight,
  /// today's checklist, best streak).
  void _syncWidgets() {
    final int bestStreak = _streaks.values.isEmpty
        ? 0
        : _streaks.values.reduce((int a, int b) => a > b ? a : b);
    syncHomeWidgets(
      quote: _content?.quote?.text,
      quoteSource: _content?.quote?.source,
      insight: _content?.insight?.text,
      insightSource: _content?.insight?.source,
      habitNames: _items.map((TodayItem item) => item.name).toList(),
      habitStates: _items.map((TodayItem item) => item.completed).toList(),
      streak: bestStreak,
    );
  }

  /// Optional enrichment: seed the streak chips from GET /habits/.
  Future<void> _enrichStreaks() async {
    try {
      final habits = await _api.habits();
      if (!mounted || habits.isEmpty) return;
      setState(() {
        for (final h in habits) {
          _streaks[h.id] = h.currentStreak;
        }
      });
    } catch (_) {
      // Streak chips stay hidden until the first toggle reveals one.
    }
  }

  Future<void> _toggle(TodayItem item) async {
    final id = item.habitId;
    if (_busyIds.contains(id)) return;
    final nowDone = !(_doneOverride[id] ?? item.completed);
    setState(() {
      _busyIds.add(id);
      _doneOverride[id] = nowDone;
    });
    try {
      final res = await _api.toggleHabit(id);
      if (!mounted) return;
      setState(() {
        _doneOverride[id] = res.completed;
        _streaks[id] = res.currentStreak;
      });
      _syncWidgets();
    } catch (_) {
      if (!mounted) return;
      setState(() => _doneOverride.remove(id));
      _toast('Could not reach MURA - change not saved.');
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
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

  String _greetingFor(DateTime now) {
    if (now.hour < 12) return 'Good morning.';
    if (now.hour < 17) return 'Good afternoon.';
    return 'Good evening.';
  }

  String get _dateLabel {
    final now = DateTime.now();
    return "${_weekdays[now.weekday - 1]} \u00b7 ${_months[now.month - 1]} ${now.day}";
  }

  void _startMotionTimer() {
    _motionTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted ||
          _motionPaused ||
          _motionQuotes.length < 2 ||
          !_motionController.hasClients) {
        return;
      }
      final next = (_motionIndex + 1) % _motionQuotes.length;
      _motionController.animateToPage(
        next,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInOut,
      );
    });
  }

  void _restartMotionTimer() {
    _motionTimer?.cancel();
    _startMotionTimer();
  }

  void _setMotionPaused(bool paused) {
    if (!mounted) return;
    setState(() => _motionPaused = paused);
    if (paused) {
      _motionTimer?.cancel();
    } else {
      _restartMotionTimer();
    }
  }

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
    if (_loading && _items.isEmpty && _error == null) {
      body = const Center(child: _LoadingView());
    } else if (_error != null && _items.isEmpty) {
      body = _ErrorState(message: _error!, onRetry: () => _load());
    } else {
      body = RefreshIndicator(
        onRefresh: () => _load(silent: true),
        color: _pal.amber,
        backgroundColor: _pal.card,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            _buildHeader(),
            const SizedBox(height: 22),
            _buildQuoteCard(),
            if (_motionQuotes.isNotEmpty) ...[
              const SizedBox(height: 18),
              _buildMotionQuotesDesigned(),
            ],
            const SizedBox(height: 30),
            _buildChecklistSection(),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(child: body),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department, color: _pal.amberDeep, size: 15),
            SizedBox(width: 6),
            Text(
              'MURA',
              style: TextStyle(
                color: _pal.amber,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _greetingFor(DateTime.now()),
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _dateLabel,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildQuoteCard() {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final quote = _content?.quote;
    final text = quote?.text ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final source = quote?.source ?? '';

    final hidden = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.format_quote, color: scheme.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'DAILY QUOTE',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            Spacer(),
            Icon(Icons.visibility_outlined,
                color: scheme.onSurfaceVariant, size: 16),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          "Tap to reveal today's reflection",
          style: TextStyle(
            color: light ? scheme.primary : const Color(0xCCFFC174),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );

    final revealed = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.format_quote, color: scheme.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'DAILY QUOTE',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            Spacer(),
            Icon(Icons.visibility, color: scheme.primary, size: 16),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '"$text"',
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 16.5,
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '- $source',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? [scheme.surfaceContainer, scheme.surfaceContainerHigh]
              : const [Color(0xFF1E160C), Color(0xFF261B0F)],
        ),
        border: Border.all(
          color: light ? scheme.outlineVariant : const Color(0x33FFC174),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _revealed = !_revealed),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: AnimatedCrossFade(
                duration: const Duration(milliseconds: 320),
                sizeCurve: Curves.easeOutCubic,
                crossFadeState: _revealed
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: hidden,
                secondChild: revealed,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMotionQuotesDesigned() {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 2, bottom: 12),
          child: Text(
            'MOTION QUOTES',
            style: TextStyle(
              color: _pal.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
        AspectRatio(
          aspectRatio: 4 / 5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: GestureDetector(
                onLongPressStart: (_) => _setMotionPaused(true),
                onLongPressEnd: (_) => _setMotionPaused(false),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedBuilder(
                      animation: _motionController,
                      builder: (context, child) {
                        final page = _motionController.hasClients
                            ? (_motionController.page ??
                                _motionIndex.toDouble())
                            : _motionIndex.toDouble();
                        return _LiquidMotionBackground(
                          paused: _motionPaused,
                          transition: (page - page.round()).abs(),
                        );
                      },
                    ),
                    Container(
                      color: light
                          ? const Color(0x14000000)
                          : const Color(0x33000000),
                    ),
                    PageView.builder(
                      controller: _motionController,
                      itemCount: _motionQuotes.length,
                      onPageChanged: (index) {
                        setState(() => _motionIndex = index);
                        if (!_motionPaused) _restartMotionTimer();
                      },
                      itemBuilder: (context, index) {
                        final item = _motionQuotes[index];
                        return AnimatedBuilder(
                          animation: _motionController,
                          builder: (context, child) {
                            final page = _motionController.hasClients
                                ? (_motionController.page ??
                                    _motionIndex.toDouble())
                                : _motionIndex.toDouble();
                            final delta = (page - index).clamp(-1.0, 1.0);
                            final progress = delta.abs();
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..translateByDouble(
                                  delta * 42,
                                  progress * 4,
                                  0,
                                  1,
                                )
                                ..rotateY(delta * 0.08)
                                ..rotateZ(delta * 0.025)
                                ..scaleByDouble(
                                  1 - progress * 0.08,
                                  1 - progress * 0.08,
                                  1,
                                  1,
                                ),
                              child: ClipPath(
                                clipper: _LiquidClipper(delta),
                                child: child,
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    _MotionControl(
                                      icon: _motionPaused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      onTap: () =>
                                          _setMotionPaused(!_motionPaused),
                                    ),
                                    const Spacer(),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0x66000000),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        child: Text(
                                          '${index + 1}/${_motionQuotes.length}',
                                          style: TextStyle(
                                            color: light
                                                ? scheme.onSurface
                                                : _pal.text,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                const Text(
                                  '"',
                                  style: TextStyle(
                                    color: Color(0x66FFC174),
                                    fontSize: 64,
                                    height: .7,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  '"${item.text}"',
                                  textAlign: TextAlign.center,
                                  maxLines: 7,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        light ? scheme.onSurface : Colors.white,
                                    fontSize: 18,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (item.source.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Text(
                                    '- ${item.source}',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: light
                                          ? scheme.onSurfaceVariant
                                          : const Color(0xB3FFFFFF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                Text(
                                  _motionPaused
                                      ? 'HOLD TO RESUME'
                                      : 'SWIPE TO EXPLORE',
                                  style: TextStyle(
                                    color: light
                                        ? scheme.onSurfaceVariant
                                        : const Color(0x99FFFFFF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistSection() {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final total = _items.length;
    var done = 0;
    for (final it in _items) {
      if (_doneOverride[it.habitId] ?? it.completed) done++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              "TODAY'S CHECKLIST",
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const Spacer(),
            Text(
              '$done/$total',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: total > 0 ? done / total : 0,
            minHeight: 4,
            backgroundColor: light ? scheme.surfaceContainerHighest : _pal.cardAlt,
            valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
          ),
        ),
        const SizedBox(height: 16),
        if (total == 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: light ? scheme.surfaceContainer : _pal.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x12FFFFFF)),
            ),
            child: Column(
              children: [
                Icon(Icons.emoji_events_outlined,
                    color: scheme.onSurfaceVariant, size: 30),
                SizedBox(height: 10),
                Text(
                  'No habits scheduled today.',
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
                ),
              ],
            ),
          )
        else
          ..._buildRows(),
      ],
    );
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];
    for (var i = 0; i < _items.length; i++) {
      rows.add(_buildHabitRow(_items[i]));
      if (i < _items.length - 1) rows.add(const SizedBox(height: 10));
    }
    return rows;
  }

  Widget _buildHabitRow(TodayItem item) {
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final done = _doneOverride[item.habitId] ?? item.completed;
    final busy = _busyIds.contains(item.habitId);
    final streak = _streaks[item.habitId];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: light ? scheme.surfaceContainer : _pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: light
              ? scheme.outlineVariant.withAlpha(90)
              : const Color(0x12FFFFFF),
        ),
      ),
      child: Row(
        children: [
          _buildCheckbox(done, busy, () => _toggle(item)),
          const SizedBox(width: 12),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: light ? scheme.surfaceContainerHigh : _pal.cardAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _iconFor(item.icon),
              size: 19,
              color: light ? scheme.onSurfaceVariant : const Color(0xFFD8C3AD),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: done ? scheme.onSurfaceVariant : scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _pal.amber,
              ),
            )
          else if (streak != null)
            _buildStreakChip(streak),
        ],
      ),
    );
  }

  Widget _buildCheckbox(bool done, bool busy, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        // easeOutBack overshoots (t > 1), which lerps the box shadow's blur
        // radius negative and trips a dart:ui assertion on un-check. The
        // bounce personality lives on the AnimatedScale below instead.
        curve: Curves.easeOutCubic,
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? _pal.amberDeep : Colors.transparent,
          border: Border.all(
            width: 1.6,
            color: done ? _pal.amberDeep : _pal.outline,
          ),
          boxShadow: done
              ? const [
                  BoxShadow(color: Color(0x40F59E0B), blurRadius: 12),
                ]
              : null,
        ),
        child: AnimatedScale(
          scale: done ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Icon(Icons.check, size: 17, color: _pal.onAmber),
        ),
      ),
    );
  }

  Widget _buildStreakChip(int streak) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x26FFC174),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 13, color: _pal.amber),
          const SizedBox(width: 3),
          Text(
            '$streak',
            style: TextStyle(
              color: _pal.amber,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
      children: [
        CircularProgressIndicator(color: Color(0xFFF59E0B), strokeWidth: 2.6),
        SizedBox(height: 16),
        Text(
          'Loading your day...',
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

class _LiquidClipper extends CustomClipper<Path> {
  const _LiquidClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final wave = progress * 16.0;
    final path = Path()..moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * .30);
    path.cubicTo(
      size.width + wave,
      size.height * .45,
      size.width - wave,
      size.height * .62,
      size.width,
      size.height * .78,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, size.height * .72);
    path.cubicTo(
      -wave,
      size.height * .56,
      wave,
      size.height * .38,
      0,
      size.height * .22,
    );
    return path..close();
  }

  @override
  bool shouldReclip(covariant _LiquidClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _MotionControl extends StatelessWidget {
  const _MotionControl({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    return Material(
      color: const Color(0x66000000),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _LiquidMotionBackground extends StatefulWidget {
  const _LiquidMotionBackground({
    required this.paused,
    required this.transition,
  });

  final bool paused;
  final double transition;

  @override
  State<_LiquidMotionBackground> createState() =>
      _LiquidMotionBackgroundState();
}

class _LiquidMotionBackgroundState extends State<_LiquidMotionBackground>
    with SingleTickerProviderStateMixin {
  MuraPalette get _pal => MuraPalette.of(context);
  ui.FragmentShader? _shader;
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    _loadShader();
    if (!widget.paused) _clock.repeat();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset(
      'assets/shaders/liquid_transition.frag',
    );
    if (!mounted) return;
    setState(() => _shader = program.fragmentShader());
  }

  @override
  void didUpdateWidget(covariant _LiquidMotionBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused == oldWidget.paused) return;
    if (widget.paused) {
      _clock.stop();
    } else {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shader == null) {
      return ColoredBox(
        color: Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFF9F9F9)
            : const Color(0xFF111111),
      );
    }
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => CustomPaint(
        painter: _LiquidShaderPainter(
          shader: _shader!,
          time: _clock.value * 12,
          transition: widget.transition,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _LiquidShaderPainter extends CustomPainter {
  const _LiquidShaderPainter({
    required this.shader,
    required this.time,
    required this.transition,
    required this.dark,
  });

  final ui.FragmentShader shader;
  final double time;
  final double transition;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, time);
    shader.setFloat(1, size.width);
    shader.setFloat(2, size.height);
    shader.setFloat(3, transition);
    shader.setFloat(4, dark ? 1 : 0);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidShaderPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.transition != transition ||
      oldDelegate.dark != dark;
}

class _LegacyLiquidMotionBackground extends StatefulWidget {
  const _LegacyLiquidMotionBackground({required this.paused});

  final bool paused;

  @override
  State<_LegacyLiquidMotionBackground> createState() =>
      _LegacyLiquidMotionBackgroundState();
}

class _LegacyLiquidMotionBackgroundState
    extends State<_LegacyLiquidMotionBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void initState() {
    super.initState();
    if (widget.paused) _controller.stop();
  }

  @override
  void didUpdateWidget(covariant _LegacyLiquidMotionBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused == oldWidget.paused) return;
    if (widget.paused) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _LegacyLiquidMotionPainter(
          _controller.value,
          Theme.of(context).brightness == Brightness.light,
        ),
      ),
    );
  }
}

class _LegacyLiquidMotionPainter extends CustomPainter {
  const _LegacyLiquidMotionPainter(this.progress, this.isLight);

  final double progress;
  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * math.pi * 2;
    final rect = Offset.zero & size;
    final base = isLight ? const Color(0xFFF9F9F9) : const Color(0xFF0B0B0B);
    final warm = isLight ? const Color(0xFFD4A373) : const Color(0xFF8C5427);
    final deep = isLight ? const Color(0xFF825526) : const Color(0xFF321B0D);
    canvas.drawRect(
      rect,
      Paint()..color = base,
    );

    void blob(Offset center, double radius, Color color) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withAlpha(230),
              color.withAlpha(95),
              color.withAlpha(0),
            ],
            stops: const [0, .62, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    blob(
      Offset(
        size.width * (.18 + .18 * math.sin(t)),
        size.height * (.20 + .10 * math.cos(t)),
      ),
      size.width * .58,
      warm,
    );
    blob(
      Offset(
        size.width * (.84 + .14 * math.cos(t * .75)),
        size.height * (.72 + .16 * math.sin(t * .75)),
      ),
      size.width * .66,
      deep,
    );
    blob(
      Offset(
        size.width * (.48 + .16 * math.sin(t * 1.25)),
        size.height * (.52 + .12 * math.cos(t * 1.1)),
      ),
      size.width * .42,
      isLight ? const Color(0xFFB98355) : const Color(0xFF6B3515),
    );

    void wave(double y, double height, double phase, Color color) {
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 8) {
        final normalized = x / size.width;
        final waveY = y +
            math.sin(normalized * math.pi * 2.4 + t * 1.3 + phase) * height +
            math.sin(normalized * math.pi * 5.2 - t + phase) * height * .35;
        path.lineTo(x, waveY);
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    wave(
      size.height * (.38 + .08 * math.sin(t)),
      size.height * .08,
      0,
      isLight ? const Color(0x507C4B2B) : const Color(0x553D1C0C),
    );
    wave(
      size.height * (.64 + .06 * math.cos(t * .8)),
      size.height * .06,
      2,
      isLight ? const Color(0x407E5535) : const Color(0x4430180A),
    );
  }

  @override
  bool shouldRepaint(covariant _LegacyLiquidMotionPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isLight != isLight;
}
