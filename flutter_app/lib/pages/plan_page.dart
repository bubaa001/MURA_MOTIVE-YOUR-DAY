/// MURA — Plan page: today's priorities + long-term goals.
///
/// Assumes the shared `api` singleton from ../api.dart exposes:
///   listPriorities() -> List`<Priority`>
///   createPriority(Map`<String, dynamic`>) -> Priority
///   updatePriority(int id, Map`<String, dynamic`>) -> Priority
///   deletePriority(int id) -> Future`<void`>
///   reorderPriorities(List`<int`> orderedIds) -> Future`<void`>
///   listGoals() -> List`<Goal`>
///   createGoal(Map`<String, dynamic`>) -> Goal
///   deleteGoal(int id) -> Future`<void`>
///   completeGoal(int id) -> Goal
/// And ../models.dart types:
///   Priority {id, title, category, completed, date}
///   Goal     {id, title, description, category, targetDate, status, progress}
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../api.dart';
import '../refresh_bus.dart';
import '../widgets/mura_widgets.dart';
import '../models.dart';
import '../theme.dart'; // ignore: unused_import -- shared tokens land here later.

// ---------------------------------------------------------------------------
// Obsidian & Amber palette (self-contained so pages stay stable while
// theme.dart evolves). Backgrounds are the #0D0B09 family, accents amber.
// ---------------------------------------------------------------------------

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _fmtDate(String? iso, {bool withYear = false}) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  final suffix = withYear ? ' ${d.year}' : '';
  return '${_months[d.month - 1]} ${d.day}$suffix';
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2A2117),
      content: Text(msg, style: TextStyle(color: MuraPalette.of(context).text)),
    ));
}

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> with AppRefreshListener {
  MuraPalette get _pal => MuraPalette.of(context);
  int _tab = 0;

  // Priorities state.
  List<Priority>? _priorities;
  bool _busyP = false;
  String? _errP;
  final Set<int> _savingP = {};

  // Goals state.
  List<Goal>? _goals;
  bool _busyG = false;
  String? _errG;

  @override
  void initState() {
    super.initState();
    _loadPriorities();
    _loadGoals();
  }

  @override
  void onAppRefresh() {
    _loadPriorities();
    _loadGoals();
  }

  Future<void> _loadPriorities() async {
    setState(() {
      _busyP = true;
      _errP = null;
    });
    try {
      final items = await api.listPriorities();
      if (!mounted) return;
      setState(() {
        _priorities = items;
        _busyP = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errP = friendlyError(e);
        _busyP = false;
      });
    }
  }

  Future<void> _loadGoals() async {
    setState(() {
      _busyG = true;
      _errG = null;
    });
    try {
      final items = await api.listGoals();
      if (!mounted) return;
      setState(() {
        _goals = items;
        _busyG = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errG = friendlyError(e);
        _busyG = false;
      });
    }
  }

  // ----------------------------- Priorities --------------------------------

  Future<void> _togglePriority(Priority p) async {
    if (_savingP.contains(p.id)) return;
    setState(() => _savingP.add(p.id));
    try {
      await api.updatePriority(p.id, {'completed': !p.completed});
      await _loadPriorities();
    } catch (_) {
      if (mounted) _toast(context, 'Could not update priority');
    } finally {
      if (mounted) {
        setState(() => _savingP.remove(p.id));
      }
    }
  }

  /// onReorderItem hands back an insertion index already adjusted for the
  /// removed item, so no manual newIndex correction happens here.
  Future<void> _onReorderItem(int oldIndex, int newIndex) async {
    final list = [...?_priorities];
    if (list.length < 2) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() => _priorities = list);
    try {
      await api.reorderPriorities(list.map((e) => e.id).toList());
    } catch (_) {
      if (mounted) _toast(context, 'Could not save order');
      _loadPriorities();
    }
  }

  Future<void> _deletePriority(Priority p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B140D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete priority?',
            style: TextStyle(
                color: _pal.text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('"${p.title}" will be removed from today.',
            style: TextStyle(color: _pal.textDim, fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: _pal.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: Color(0xFFFF8A80), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(
        () => _priorities = _priorities!.where((x) => x.id != p.id).toList());
    try {
      await api.deletePriority(p.id);
    } catch (_) {
      if (mounted) _toast(context, 'Could not delete priority');
      _loadPriorities();
    }
  }

  Future<void> _addPriority() async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AddPriorityDialog(),
    );
    if (body == null || !mounted) return;
    try {
      await api.createPriority(
        title: body['title'] as String? ?? '',
        category: body['category'] as String?,
      );
      await _loadPriorities();
      if (mounted) _toast(context, 'Priority locked in');
    } catch (_) {
      if (mounted) _toast(context, 'Could not add priority');
    }
  }

  // -------------------------------- Goals ----------------------------------

  Future<void> _completeGoal(Goal g) async {
    try {
      await api.completeGoal(g.id);
      await _loadGoals();
      if (mounted) _showCelebration(g);
    } catch (_) {
      if (mounted) _toast(context, 'Could not complete goal');
    }
  }

  Future<void> _deleteGoal(Goal g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B140D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete goal?',
            style: TextStyle(
                color: _pal.text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('"${g.title}" will be removed permanently.',
            style: TextStyle(color: _pal.textDim, fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: _pal.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: Color(0xFFFF8A80), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _goals = _goals!.where((x) => x.id != g.id).toList());
    try {
      await api.deleteGoal(g.id);
    } catch (_) {
      if (mounted) _toast(context, 'Could not delete goal');
      _loadGoals();
    }
  }

  Future<void> _addGoal() async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AddGoalDialog(),
    );
    if (body == null || !mounted) return;
    try {
      await api.createGoal(
        title: body['title'] as String? ?? '',
        goalType: body['goal_type'] as String? ?? 'personal_development',
        horizon: body['horizon'] as String? ?? 'short',
        category: body['category'] as String?,
        progress: body['progress'] as int? ?? 0,
        targetDate: body['target_date'] as String?,
      );
      await _loadGoals();
      if (mounted) _toast(context, 'Goal set. Chase it.');
    } catch (_) {
      if (mounted) _toast(context, 'Could not add goal');
    }
  }

  void _showCelebration(Goal g) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (_) => _CelebrationDialog(goalTitle: g.title),
    );
  }

  // -------------------------------- Build ----------------------------------

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, landscape ? 8 : 20, 20, 6),
              child: _Segmented(
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  RefreshIndicator(
                    color: _pal.amber,
                    backgroundColor: _pal.cardHi,
                    onRefresh: _loadPriorities,
                    child: _buildPrioritiesBody(),
                  ),
                  RefreshIndicator(
                    color: _pal.amber,
                    backgroundColor: _pal.cardHi,
                    onRefresh: _loadGoals,
                    child: _buildGoalsBody(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrioritiesBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
          child: Row(
            children: [
              Text('PRIORITIES',
                  style: TextStyle(
                      color: _pal.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
              const Spacer(),
              IconButton(
                onPressed: _addPriority,
                icon: Icon(Icons.add_circle, color: _pal.amber, size: 26),
                tooltip: 'Add priority',
              ),
            ],
          ),
        ),
        _buildSummaryCard(),
        Expanded(child: _prioritiesList()),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final items = _priorities ?? const [];
    final done = items.where((p) => p.completed).length;
    final frac = items.isEmpty ? 0.0 : done / items.length;
    final now = DateTime.now();
    final todayLabel = '${_months[now.month - 1]} ${now.day}, ${now.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _pal.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Today · $todayLabel',
                    style: TextStyle(
                        color: _pal.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                Text('$done / ${items.length} done',
                    style: TextStyle(
                        color: _pal.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedProgressBar(value: frac, height: 6, color: _pal.amber),
          ],
        ),
      ),
    );
  }

  Widget _prioritiesList() {
    if (_busyP && _priorities == null) {
      return Center(child: CircularProgressIndicator(color: _pal.amber));
    }
    if (_errP != null) {
      return ListView(children: [_errorBox(_errP!, _loadPriorities)]);
    }
    final items = _priorities ?? const [];
    if (items.isEmpty) {
      return ListView(children: [
        _emptyBox(Icons.flag_rounded, 'No priorities yet',
            'Tap + to name what matters most today.'),
      ]);
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: true,
      itemCount: items.length,
      onReorderItem: _onReorderItem,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (_, __) => Material(
          color: Colors.transparent,
          elevation: 6,
          shadowColor: _pal.amberDeep.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      ),
      itemBuilder: (ctx, i) {
        final p = items[i];
        return KeyedSubtree(
          key: ValueKey('priority-${p.id}'),
          child: Dismissible(
            key: ValueKey('dismiss-${p.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF3A1410),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.delete_outline, color: Color(0xFFFF8A80)),
            ),
            confirmDismiss: (_) async {
              await _deletePriority(p);
              return false; // removal handled via API reload
            },
            child: _PriorityTile(
              priority: p,
              saving: _savingP.contains(p.id),
              onToggle: () => _togglePriority(p),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGoalsBody() {
    final scheme = Theme.of(context).colorScheme;
    if (_busyG && _goals == null) {
      return Center(child: CircularProgressIndicator(color: _pal.amber));
    }
    if (_errG != null) {
      return ListView(children: [_errorBox(_errG!, _loadGoals)]);
    }
    final goals = _goals ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      children: [
        Row(
          children: [
            Text('GOALS',
                style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
            const Spacer(),
            IconButton(
              onPressed: _addGoal,
              icon: Icon(Icons.add_circle, color: scheme.primary, size: 26),
              tooltip: 'Add goal',
            ),
          ],
        ),
        if (goals.isEmpty)
          _emptyBox(Icons.emoji_events_outlined, 'No goals yet',
              'Set a target worth grinding for.'),
        for (final g in goals)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _GoalCard(
              goal: g,
              onComplete: () => _completeGoal(g),
              onDelete: () => _deleteGoal(g),
            ),
          ),
      ],
    );
  }

  Widget _errorBox(String msg, Future<void> Function() retry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, color: _pal.textDim, size: 36),
          const SizedBox(height: 12),
          Text('Something broke: $msg',
              textAlign: TextAlign.center,
              style: TextStyle(color: _pal.textDim, fontSize: 12.5)),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: retry,
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: _pal.amber)),
            child: Text('Retry', style: TextStyle(color: _pal.amber)),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox(IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
      child: Column(
        children: [
          Icon(icon, color: _pal.textDim.withValues(alpha: .7), size: 38),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: _pal.text, fontSize: 15.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: _pal.textDim, fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }
}

// =============================== Widgets ===================================

class _Segmented extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _Segmented({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    Widget seg(String label, IconData icon, int i) {
      final selected = i == index;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: selected
                  ? LinearGradient(colors: [pal.amber, pal.amberDeep])
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: selected ? pal.onAmber : pal.textDim),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? pal.onAmber : pal.textDim)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF15100A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: pal.stroke),
      ),
      child: Row(
        children: [
          seg('Priorities', Icons.flag_rounded, 0),
          seg('Goals', Icons.track_changes_rounded, 1),
        ],
      ),
    );
  }
}

class _PriorityTile extends StatelessWidget {
  final Priority priority;
  final bool saving;
  final VoidCallback onToggle;

  const _PriorityTile({
    required this.priority,
    required this.saving,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    final p = priority;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(8, 12, 6, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.stroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 0.95,
            child: Checkbox(
              value: p.completed,
              onChanged: saving ? null : (_) => onToggle(),
              activeColor: pal.amber,
              checkColor: pal.onAmber,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              side: BorderSide(color: pal.textDim, width: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.completed ? pal.textDim : pal.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          decoration:
                              p.completed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (saving)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: pal.amber),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                AnimatedProgressBar(
                  value: p.completed ? 1.0 : 0.04,
                  height: 3,
                  color: pal.amber,
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pal.amber.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(p.category,
                          style: TextStyle(
                              color: pal.amber,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.event_note_rounded,
                        size: 12, color: pal.textDim.withValues(alpha: .9)),
                    const SizedBox(width: 4),
                    Text(_fmtDate(p.date, withYear: true),
                        style: TextStyle(color: pal.textDim, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.drag_indicator_rounded,
              size: 18, color: pal.textDim.withValues(alpha: .55)),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.goal,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    final g = goal;
    final scheme = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final double frac = ((g.progress) / 100).clamp(0.0, 1.0).toDouble();
    final achieved = g.status == 'achieved';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? [scheme.surfaceContainerHigh, scheme.surfaceContainer]
              : [pal.card, pal.cardHi],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: light ? scheme.outlineVariant.withAlpha(100) : pal.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(status: g.status),
              const Spacer(),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.delete_outline,
                    size: 19, color: pal.textDim.withValues(alpha: .8)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(g.title,
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(
            '${_goalTypeLabel(g.goalType)} · ${g.horizon == 'long' ? 'Long range' : 'Short range'}',
            style: TextStyle(
              color: scheme.primary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
            ),
          ),
          if (g.description.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(g.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.35)),
          ],
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(Icons.flag_outlined,
                  size: 12, color: pal.textDim.withValues(alpha: .9)),
              const SizedBox(width: 4),
              Text(
                (g.targetDate ?? '').isEmpty
                    ? 'No deadline'
                    : 'Due ${_fmtDate(g.targetDate, withYear: true)}',
                style:
                    TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: frac),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      backgroundColor: light
                          ? scheme.surfaceContainerHighest
                          : const Color(0xFF2A2013),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          achieved ? pal.teal : pal.amber),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${g.progress}%',
                  style: TextStyle(
                      color: achieved ? pal.teal : pal.amber,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          if (achieved)
            Container(
              height: 42,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pal.teal.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: pal.teal.withValues(alpha: .35)),
              ),
              child: Text('Achieved · discipline pays',
                  style: TextStyle(
                      color: pal.teal,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            )
          else
            SizedBox(
              height: 44,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: pal.amber,
                  foregroundColor: pal.onAmber,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Mark complete',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }

  String _goalTypeLabel(String value) => switch (value) {
        'chief_aim' => 'Definite chief aim',
        'economic' => 'Economic',
        'things' => 'Things',
        _ => 'Personal development',
      };
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) { final MuraPalette pal = MuraPalette.of(context);
    final Color c;
    final String label;
    switch (status) {
      case 'achieved':
        c = pal.teal;
        label = 'ACHIEVED';
        break;
      case 'abandoned':
        c = pal.textDim;
        label = 'PAUSED';
        break;
      default:
        c = pal.amber;
        label = 'ACTIVE';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: .4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: c,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4)),
    );
  }
}

// ============================ Celebration ==================================

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final double spin;
  final double drift;
  final Color color;
  const _Particle(
      this.angle, this.speed, this.size, this.spin, this.drift, this.color);
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;

  _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.34;
    final maxR = size.height * 0.62;
    final paint = Paint();
    for (final pt in particles) {
      final r = t * pt.speed * maxR;
      final dx =
          cx + cos(pt.angle) * r * 1.45 + pt.drift * t * size.width * 0.25;
      final dy = cy + sin(pt.angle) * r * 0.8 + (t * t) * size.height * 0.5;
      final alpha = (1 - t).clamp(0.0, 1.0);
      paint.color = pt.color.withValues(alpha: alpha * 0.95);
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(pt.angle + t * pt.spin * 6.283);
      final s = pt.size * (1 - t * 0.45);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.55),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t;
}

class _CelebrationDialog extends StatefulWidget {
  final String goalTitle;
  const _CelebrationDialog({required this.goalTitle});

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog>
    with SingleTickerProviderStateMixin {
  MuraPalette get _pal => MuraPalette.of(context);
  late final AnimationController _ctrl;
  late final List<_Particle> _parts;

  List<Color> get _confettiColors => [
        _pal.amber,
        _pal.amberDeep,
        _pal.teal,
        const Color(0xFFC7C8FF),
        const Color(0xFFFFF3E0),
      ];

  @override
  void initState() {
    super.initState();
    final rng = Random(2026);
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat();
    _parts = List.generate(70, (_) {
      return _Particle(
        rng.nextDouble() * 6.283,
        0.45 + rng.nextDouble() * 0.75,
        3.5 + rng.nextDouble() * 5,
        rng.nextDouble(),
        rng.nextDouble() - 0.5,
        _confettiColors[rng.nextInt(_confettiColors.length)],
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1D160D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => CustomPaint(
                    painter: _ConfettiPainter(_parts, _ctrl.value),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _pal.amber.withValues(alpha: .16),
                      shape: BoxShape.circle,
                      border: Border.all(color: _pal.amber.withValues(alpha: .5)),
                    ),
                    child: const Text('🏆', style: TextStyle(fontSize: 30)),
                  ),
                  const SizedBox(height: 14),
                  Text('GOAL ACHIEVED',
                      style: TextStyle(
                          color: _pal.amber,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3)),
                  const SizedBox(height: 8),
                  Text(widget.goalTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _pal.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Discipline compounds. Onward.',
                      style: TextStyle(color: _pal.textDim, fontSize: 13)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pal.amber,
                        foregroundColor: _pal.onAmber,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text('Keep going 🔥',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================= Add dialogs =================================

class _AddPriorityDialog extends StatefulWidget {
  const _AddPriorityDialog();

  @override
  State<_AddPriorityDialog> createState() => _AddPriorityDialogState();
}

class _AddPriorityDialogState extends State<_AddPriorityDialog> {
  MuraPalette get _pal => MuraPalette.of(context);
  final TextEditingController _ctrl = TextEditingController();
  String _cat = 'Deep Work';
  static const List<String> _cats = ['Deep Work', 'Health', 'Growth', 'Admin'];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _pal.textDim, fontSize: 13.5),
        filled: true,
        fillColor: _pal.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _pal.amber, width: 1.3)),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B140D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('New priority',
          style: TextStyle(
              color: _pal.text, fontSize: 17, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            cursorColor: _pal.amber,
            style: TextStyle(color: _pal.text, fontSize: 14.5),
            onChanged: (_) => setState(() {}),
            decoration: _deco('What matters most today?'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _cats)
                ChoiceChip(
                  label: Text(c,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _cat == c ? _pal.onAmber : _pal.textDim)),
                  selected: _cat == c,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _cat = c),
                  selectedColor: _pal.amber,
                  backgroundColor: _pal.field,
                  shape: StadiumBorder(side: BorderSide(color: _pal.stroke)),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: _pal.textDim)),
        ),
        ElevatedButton(
          onPressed: _ctrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context, {'title': _ctrl.text.trim(), 'category': _cat}),
          style: ElevatedButton.styleFrom(
            backgroundColor: _pal.amber,
            foregroundColor: _pal.onAmber,
            disabledBackgroundColor: _pal.amber.withValues(alpha: .25),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child:
              const Text('Add', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _AddGoalDialog extends StatefulWidget {
  const _AddGoalDialog();

  @override
  State<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends State<_AddGoalDialog> {
  MuraPalette get _pal => MuraPalette.of(context);
  final TextEditingController _ctrl = TextEditingController();
  String _cat = 'Fitness';
  String _goalType = 'personal_development';
  String _horizon = 'short';
  DateTime? _targetDate;
  static const List<String> _cats = [
    'Fitness',
    'Mindfulness',
    'Career',
    'Finance'
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
      helpText: 'Choose when you want to achieve this goal',
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B140D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('New goal',
          style: TextStyle(
              color: _pal.text, fontSize: 17, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height * .58,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ctrl,
                autofocus: true,
                cursorColor: _pal.amber,
                style: TextStyle(color: _pal.text, fontSize: 14.5),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'e.g. Run a half marathon',
                  hintStyle: TextStyle(color: _pal.textDim, fontSize: 13.5),
                  filled: true,
                  fillColor: _pal.field,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _pal.amber, width: 1.3)),
                ),
              ),
              const SizedBox(height: 14),
              Text('Goal type',
                  style: TextStyle(color: _pal.textDim, fontSize: 11)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _goalType,
                isExpanded: true,
                dropdownColor: _pal.field,
                style: TextStyle(color: _pal.text, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _pal.field,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'chief_aim', child: Text('Definite chief aim')),
                  DropdownMenuItem(value: 'economic', child: Text('Economic')),
                  DropdownMenuItem(value: 'things', child: Text('Things')),
                  DropdownMenuItem(
                      value: 'personal_development',
                      child: Text('Personal development')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _goalType = value);
                },
              ),
              const SizedBox(height: 14),
              Text('Time horizon',
                  style: TextStyle(color: _pal.textDim, fontSize: 11)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'short', label: Text('Short range')),
                  ButtonSegment(value: 'long', label: Text('Long range')),
                ],
                selected: {_horizon},
                onSelectionChanged: (value) =>
                    setState(() => _horizon = value.first),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pickTargetDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  _targetDate == null
                      ? 'Set target date'
                      : 'Target: ${_targetDate!.day.toString().padLeft(2, '0')}/'
                          '${_targetDate!.month.toString().padLeft(2, '0')}/'
                          '${_targetDate!.year}',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _targetDate == null ? _pal.textDim : _pal.amber,
                  side: BorderSide(color: _pal.stroke),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              Text('Area',
                  style: TextStyle(color: _pal.textDim, fontSize: 11)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _cats)
                    ChoiceChip(
                      label: Text(c,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _cat == c ? _pal.onAmber : _pal.textDim)),
                      selected: _cat == c,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _cat = c),
                      selectedColor: _pal.amber,
                      backgroundColor: _pal.field,
                      shape: StadiumBorder(
                          side: BorderSide(color: _pal.stroke)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: _pal.textDim)),
        ),
        ElevatedButton(
          onPressed: _ctrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, {
                    'title': _ctrl.text.trim(),
                    'goal_type': _goalType,
                    'horizon': _horizon,
                    'category': _cat,
                    'progress': 0,
                    'status': 'active',
                    'target_date': _targetDate == null
                        ? null
                        : '${_targetDate!.year.toString().padLeft(4, '0')}-'
                            '${_targetDate!.month.toString().padLeft(2, '0')}-'
                            '${_targetDate!.day.toString().padLeft(2, '0')}',
                  }),
          style: ElevatedButton.styleFrom(
            backgroundColor: _pal.amber,
            foregroundColor: _pal.onAmber,
            disabledBackgroundColor: _pal.amber.withValues(alpha: .25),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Set goal',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
