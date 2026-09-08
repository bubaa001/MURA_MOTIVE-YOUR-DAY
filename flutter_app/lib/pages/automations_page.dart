/// MURA — Automations page (route /automations): the user's WHEN → THEN
/// rules. Creation starts from one-tap templates so a rule can be live in
/// ten seconds; every card can be toggled, edited, or deleted.
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/mura_widgets.dart';

/// One-tap recipe. Editing a template's message is allowed; the trigger
/// type stays fixed (chosen when created).
class _Template {
  const _Template({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.triggerType,
    this.triggerConfig = const <String, dynamic>{},
    required this.messageTitle,
    required this.messageBody,
  });

  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final String triggerType;
  final Map<String, dynamic> triggerConfig;
  final String messageTitle;
  final String messageBody;
}

const List<_Template> _templates = <_Template>[
  _Template(
    id: 'perfect_day',
    emoji: '🏆',
    title: 'Perfect Day',
    subtitle: 'When every habit is done',
    triggerType: 'all_habits_done',
    messageTitle: 'Perfect day. Every habit done.',
    messageBody: 'This is who you are becoming.',
  ),
  _Template(
    id: 'streak_glory',
    emoji: '🔥',
    title: 'Streak Glory',
    subtitle: 'When a streak hits 7 days',
    triggerType: 'streak_reached',
    triggerConfig: <String, dynamic>{'streak': 7},
    messageTitle: '{streak} days strong: {habit}',
    messageBody: 'Chains like this are who you are.',
  ),
  _Template(
    id: 'goal_champion',
    emoji: '🥇',
    title: 'Goal Champion',
    subtitle: 'When a goal is achieved',
    triggerType: 'goal_achieved',
    messageTitle: 'Goal achieved: {goal}',
    messageBody: 'You promised yourself. You delivered.',
  ),
  _Template(
    id: 'habit_shoutout',
    emoji: '💪',
    title: 'Habit Shoutout',
    subtitle: 'When a habit is completed',
    triggerType: 'habit_done',
    messageTitle: '{habit} — done.',
    messageBody: 'Small wins compound.',
  ),
  _Template(
    id: 'evening_nudge',
    emoji: '🌙',
    title: 'Evening Nudge',
    subtitle: 'Daily at 21:00 if habits are still open',
    triggerType: 'daily_nudge',
    triggerConfig: <String, dynamic>{'time': '21:00', 'only_if_incomplete': true},
    messageTitle: 'Habits still open',
    messageBody: 'Close the day strong — you still have time.',
  ),
];

IconData _triggerIcon(String type) {
  switch (type) {
    case 'habit_done':
      return Icons.check_circle_outline_rounded;
    case 'all_habits_done':
      return Icons.emoji_events_outlined;
    case 'streak_reached':
      return Icons.local_fire_department_outlined;
    case 'goal_achieved':
      return Icons.flag_rounded;
    case 'daily_nudge':
      return Icons.nights_stay_outlined;
    default:
      return Icons.auto_awesome_rounded;
  }
}

class AutomationsPage extends StatefulWidget {
  const AutomationsPage({super.key});

  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  MuraPalette get _pal => MuraPalette.of(context);

  List<AutomationRule> _rules = const <AutomationRule>[];
  List<Habit> _habits = const <Habit>[];
  bool _busy = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final rules = await api.automations();
      final habits = await api.habits();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _habits = habits;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = friendlyError(e);
        _busy = false;
      });
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _pal.cardHi,
        content: Text(msg, style: TextStyle(color: _pal.text)),
      ));
  }

  Future<void> _createFromTemplate(_Template t) async {
    try {
      await api.createAutomation(
        name: t.title,
        triggerType: t.triggerType,
        triggerConfig: t.triggerConfig,
        actionConfig: <String, dynamic>{
          'title': t.messageTitle,
          'body': t.messageBody,
        },
      );
      _toast('${t.emoji}  "${t.title}" is live');
      _load();
    } catch (_) {
      _toast('Could not create the automation.');
    }
  }

  Future<void> _openEditor({_Template? template, AutomationRule? rule}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _pal.cardHi,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _AutomationEditor(
        template: template,
        rule: rule,
        habits: _habits,
        onSaved: _load,
      ),
    );
    // The editor already calls onSaved after each save/delete.
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton: _rules.isEmpty || _busy
          ? null
          : FloatingActionButton.extended(
              heroTag: 'automations-fab',
              onPressed: () => _openEditor(),
              backgroundColor: _pal.amberDeep,
              foregroundColor: _pal.onAmber,
              elevation: 3,
              icon: const Icon(Icons.add, size: 24),
              label: const Text('New automation',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: _pal.amber,
          backgroundColor: _pal.cardHi,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header()),
              if (_busy)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_err != null)
                SliverToBoxAdapter(child: _errorCard())
              else if (_rules.isEmpty)
                SliverToBoxAdapter(child: _emptyState())
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                    child: Text(
                      'YOUR RULES',
                      style: TextStyle(
                          color: _pal.textDim,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2),
                    ),
                  ),
                ),
                SliverList.separated(
                  itemCount: _rules.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => FadeSlideIn(
                    index: i.clamp(0, 6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _ruleCard(_rules[i]),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_rounded, color: _pal.text, size: 22),
            tooltip: 'Back',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AUTOMATIONS',
                  style: TextStyle(
                      color: _pal.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5)),
              const SizedBox(height: 2),
              Text('Make MURA react to you',
                  style: TextStyle(color: _pal.textDim, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: MuraCard(
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, color: _pal.textDim, size: 32),
            const SizedBox(height: 10),
            Text('Could not load automations: $_err',
                textAlign: TextAlign.center,
                style: TextStyle(color: _pal.textDim, fontSize: 12)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              style:
                  OutlinedButton.styleFrom(side: BorderSide(color: _pal.amber)),
              child: Text('Retry', style: TextStyle(color: _pal.amber)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: FadeSlideIn(
        index: 0,
        child: MuraCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: _pal.amber, size: 20),
                  const SizedBox(width: 8),
                  Text('START WITH A RECIPE',
                      style: TextStyle(
                          color: _pal.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tap one to make it live instantly — you can edit the message or delete it any time.',
                style: TextStyle(color: _pal.textDim, fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              ..._templates.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Pressable(
                      onTap: () => _createFromTemplate(t),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _pal.field,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _pal.stroke),
                        ),
                        child: Row(
                          children: [
                            Text(t.emoji,
                                style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.title,
                                      style: TextStyle(
                                          color: _pal.text,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(t.subtitle,
                                      style: TextStyle(
                                          color: _pal.textDim,
                                          fontSize: 10.5)),
                                ],
                              ),
                            ),
                            Icon(Icons.add_circle_outline_rounded,
                                size: 20, color: _pal.amber),
                          ],
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ruleCard(AutomationRule rule) {
    return Pressable(
      onTap: () => _openEditor(rule: rule),
      child: MuraCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rule.isActive
                    ? _pal.amber.withValues(alpha: .13)
                    : _pal.field,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_triggerIcon(rule.triggerType),
                  size: 20,
                  color: rule.isActive ? _pal.amber : _pal.textDim),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.name,
                      style: TextStyle(
                          color: _pal.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(rule.triggerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: _pal.textDim, fontSize: 10.5)),
                  if (rule.messageTitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '“${rule.messageTitle}”',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _pal.amber.withValues(alpha: .85),
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Switch.adaptive(
              value: rule.isActive,
              activeThumbColor: _pal.amber,
              activeTrackColor: _pal.amber.withValues(alpha: 0.4),
              onChanged: (v) async {
                try {
                  final updated = await api.toggleAutomation(rule.id);
                  setState(() {
                    final i =
                        _rules.indexWhere((r) => r.id == updated.id);
                    if (i >= 0) {
                      _rules = [..._rules]..[i] = updated;
                    }
                  });
                } catch (_) {
                  _toast('Could not update the automation.');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet editor shared by "New automation", templates and edits.
class _AutomationEditor extends StatefulWidget {
  const _AutomationEditor({
    this.template,
    this.rule,
    required this.habits,
    required this.onSaved,
  });

  final _Template? template;
  final AutomationRule? rule;
  final List<Habit> habits;
  final Future<void> Function() onSaved;

  @override
  State<_AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<_AutomationEditor> {
  MuraPalette get _pal => MuraPalette.of(context);

  late String _name;
  late String _triggerType;
  late Map<String, dynamic> _triggerConfig;
  late String _messageTitle;
  late String _messageBody;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = widget.rule?.name ?? widget.template?.title ?? '';
    _triggerType =
        widget.rule?.triggerType ?? widget.template?.triggerType ?? 'habit_done';
    _triggerConfig = Map<String, dynamic>.from(
        widget.rule?.triggerConfig ?? widget.template?.triggerConfig ??
            const <String, dynamic>{});
    final action = widget.rule?.actionConfig ??
        (widget.template != null
            ? <String, dynamic>{
                'title': widget.template!.messageTitle,
                'body': widget.template!.messageBody,
              }
            : const <String, dynamic>{});
    _messageTitle = (action['title'] as String?) ?? '';
    _messageBody = (action['body'] as String?) ?? '';
    if (_triggerType == 'streak_reached' && _triggerConfig['streak'] == null) {
      _triggerConfig['streak'] = 7;
    }
    if (_triggerType == 'daily_nudge' && _triggerConfig['time'] == null) {
      _triggerConfig['time'] = '21:00';
    }
  }

  bool get _isEditing => widget.rule != null;

  Future<void> _save() async {
    if (_busy || _name.trim().isEmpty || _messageTitle.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final actionConfig = <String, dynamic>{
        'title': _messageTitle.trim(),
        'body': _messageBody.trim(),
      };
      if (_isEditing) {
        await api.updateAutomation(widget.rule!.id, <String, dynamic>{
          'name': _name.trim(),
          'trigger_type': _triggerType,
          'trigger_config': _triggerConfig,
          'action_config': actionConfig,
        });
      } else {
        await api.createAutomation(
          name: _name.trim(),
          triggerType: _triggerType,
          triggerConfig: _triggerConfig,
          actionConfig: actionConfig,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      await widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save: ${friendlyError(e)}',
            style: TextStyle(color: _pal.text)),
        backgroundColor: _pal.cardAlt,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _pal.cardHi,
        title: Text('Delete "${widget.rule?.name}"?',
            style: TextStyle(color: _pal.text, fontSize: 16)),
        content: Text('The rule stops firing immediately.',
            style: TextStyle(color: _pal.textDim, fontSize: 12.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: _pal.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: TextStyle(
                      color: _pal.coral, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await api.deleteAutomation(widget.rule!.id);
    } catch (_) {
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    await widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _pal.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isEditing ? 'Edit automation' : 'New automation',
              style: TextStyle(
                  color: _pal.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _label('NAME'),
            _field(
              'e.g. Perfect Day celebration',
              initial: _name,
              onChanged: (v) => _name = v,
            ),
            const SizedBox(height: 16),
            _label('WHEN'),
            if (!_isEditing)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AutomationRule.triggerTypes.map((t) {
                  final selected = t == _triggerType;
                  return _pill(
                    _triggerLabelShort(t),
                    selected,
                    () => setState(() {
                      _triggerType = t;
                      _triggerConfig = switch (t) {
                        'streak_reached' => <String, dynamic>{'streak': 7},
                        'daily_nudge' => <String, dynamic>{
                            'time': '21:00',
                            'only_if_incomplete': false,
                          },
                        _ => <String, dynamic>{},
                      };
                    }),
                  );
                }).toList(),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_triggerLabelLong(),
                    style: TextStyle(color: _pal.textDim, fontSize: 12)),
              ),
            if (_triggerType == 'streak_reached') ...[
              const SizedBox(height: 12),
              _label('STREAK LENGTH (DAYS)'),
              _field(
              '7',
              initial: '${_triggerConfig['streak'] ?? 7}',
                digitsOnly: true,
                onChanged: (v) =>
                    _triggerConfig['streak'] = int.tryParse(v) ?? 7,
              ),
            ],
            if (_triggerType == 'daily_nudge') ...[
              const SizedBox(height: 12),
              _label('TIME'),
              Pressable(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: int.tryParse(
                              (_triggerConfig['time'] as String?)
                                  ?.split(':')
                                  .first ??
                                  '21') ??
                          21,
                      minute: int.tryParse(
                              (_triggerConfig['time'] as String?)
                                  ?.split(':')
                                  .last ??
                                  '00') ??
                          0,
                    ),
                  );
                  if (picked != null) {
                    setState(() {
                      _triggerConfig['time'] =
                          '${picked.hour.toString().padLeft(2, '0')}:'
                          '${picked.minute.toString().padLeft(2, '0')}';
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _pal.field,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _pal.stroke),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 18, color: _pal.amber),
                      const SizedBox(width: 8),
                      Text(
                          'Every day at ${_triggerConfig['time'] ?? '21:00'}',
                          style:
                              TextStyle(color: _pal.text, fontSize: 13.5)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: (_triggerConfig['only_if_incomplete'] as bool?) ?? false,
                onChanged: (v) => setState(() =>
                    _triggerConfig['only_if_incomplete'] = v),
                activeColor: _pal.amber,
                contentPadding: EdgeInsets.zero,
                title: Text('Only if habits are still open',
                    style: TextStyle(color: _pal.text, fontSize: 13)),
                subtitle: Text('Hold the nudge when your day is complete',
                    style: TextStyle(color: _pal.textDim, fontSize: 10.5)),
              ),
            ],
            if (_triggerType == 'habit_done' ||
                _triggerType == 'streak_reached') ...[
              const SizedBox(height: 8),
              _label('HABIT (OPTIONAL — LEAVE EMPTY FOR ANY)'),
              ..._habitChoices(),
            ],
            const SizedBox(height: 16),
            _label('THEN, SEND ME'),
            _field(
              'Title — {habit}, {streak}, {goal} become real values',
              initial: _messageTitle,
              onChanged: (v) => _messageTitle = v,
            ),
            const SizedBox(height: 8),
            _field(
              'Message (optional)',
              initial: _messageBody,
              onChanged: (v) => _messageBody = v,
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: _busy ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _pal.amber,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: _busy
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _pal.onAmber))
                          : Text(
                              _isEditing ? 'Save changes' : 'Create rule',
                              style: TextStyle(
                                  color: _pal.onAmber,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ),
                if (_isEditing) ...[
                  const SizedBox(width: 10),
                  Pressable(
                    onTap: _delete,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _pal.coral.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(Icons.delete_outline_rounded,
                          size: 20, color: _pal.coral),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _habitChoices() {
    final choices = <Widget>[
      _pill('Any habit', _triggerConfig['habit_id'] == null, () {
        setState(() => _triggerConfig.remove('habit_id'));
      }),
    ];
    for (final h in widget.habits) {
      final selected = _triggerConfig['habit_id'] == h.id;
      choices.add(_pill(h.name, selected, () {
        setState(() => _triggerConfig['habit_id'] = h.id);
      }));
    }
    return [
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: choices),
    ];
  }

  String _triggerLabelShort(String t) {
    switch (t) {
      case 'habit_done':
        return 'Habit done';
      case 'all_habits_done':
        return 'All habits done';
      case 'streak_reached':
        return 'Streak hits N';
      case 'goal_achieved':
        return 'Goal achieved';
      case 'daily_nudge':
        return 'Daily nudge';
      default:
        return t;
    }
  }

  String _triggerLabelLong() {
    switch (_triggerType) {
      case 'habit_done':
        return 'When a habit is completed';
      case 'all_habits_done':
        return 'When all of today\'s habits are done';
      case 'streak_reached':
        return 'When a streak reaches ${_triggerConfig['streak']} days';
      case 'goal_achieved':
        return 'When a goal is achieved';
      case 'daily_nudge':
        return 'Every day at ${_triggerConfig['time']}';
      default:
        return _triggerType;
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: _pal.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6)),
      );

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _pal.amber : _pal.field,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected ? _pal.amber : _pal.stroke),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: selected ? _pal.onAmber : _pal.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _field(
    String hint, {
    String? initial,
    void Function(String)? onChanged,
    bool digitsOnly = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      initialValue: initial,
      maxLines: maxLines,
      keyboardType: digitsOnly ? TextInputType.number : null,
      cursorColor: _pal.amber,
      style: TextStyle(color: _pal.text, fontSize: 14),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _pal.textDim, fontSize: 12.5),
        filled: true,
        fillColor: _pal.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _pal.amber, width: 1.2)),
      ),
    );
  }
}
