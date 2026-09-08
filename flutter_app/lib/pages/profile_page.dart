/// MURA — Profile page (route /settings): hero identity card, discipline
/// stats, achievements, and account actions. Reached from the top-bar
/// avatar; the Automations tile opens /automations.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api.dart';
import '../models.dart';
import '../refresh_bus.dart';
import '../theme.dart';
import '../widgets/mura_widgets.dart';

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MuraPalette.of(context).cardHi,
      content: Text(msg, style: TextStyle(color: MuraPalette.of(context).text)),
    ));
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  MuraPalette get _pal => MuraPalette.of(context);

  UserProfile? _me;
  List<Habit> _habits = const <Habit>[];
  List<Goal> _goals = const <Goal>[];
  int _journalCount = 0;
  bool _busy = false;
  String? _err;
  bool _loggingOut = false;
  String _version = '';

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
      // Profile + stats land in parallel; the whole page is one round trip.
      final results = await Future.wait<Object?>([
        api.me(),
        api.habits(),
        api.goals(),
        api.listJournalEntries(),
      ]);
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _me = results[0] as UserProfile;
        _habits = results[1] as List<Habit>;
        _goals = results[2] as List<Goal>;
        _journalCount = (results[3] as List<JournalEntry>).length;
        _version = '${info.version} (${info.buildNumber})';
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

  String get _name => _me?.effectiveName ?? '';
  String get _initial => _name.isEmpty ? 'B' : _name[0].toUpperCase();

  String get _joined {
    final d = DateTime.tryParse(_me?.dateJoined ?? '');
    if (d == null) return '';
    return '${_months[d.month - 1]} ${d.year}';
  }

  // ----- stats -----

  int get _bestStreak =>
      _habits.fold<int>(0, (m, h) => h.bestStreak > m ? h.bestStreak : m);

  int get _activeHabits => _habits.where((h) => h.isActive).length;

  int get _goalsAchieved =>
      _goals.where((g) => g.status == 'achieved').length;

  List<({String label, IconData icon, bool earned})> get _achievements {
    final best = _bestStreak;
    return [
      (label: 'First habit', icon: Icons.flag_rounded, earned: _habits.isNotEmpty),
      (label: '7-day streak', icon: Icons.local_fire_department_rounded, earned: best >= 7),
      (label: '30-day streak', icon: Icons.whatshot_rounded, earned: best >= 30),
      (label: 'First goal', icon: Icons.verified_rounded, earned: _goalsAchieved > 0),
      (label: '10 journals', icon: Icons.book_rounded, earned: _journalCount >= 10),
      (label: '100-day streak', icon: Icons.workspace_premium_rounded, earned: best >= 100),
    ];
  }

  // ----- actions -----

  Future<void> _editDisplayName() async {
    final ctrl = TextEditingController(text: _me?.displayName ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _pal.cardHi,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Display name',
            style: TextStyle(
                color: _pal.text, fontSize: 17, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          cursorColor: _pal.amber,
          maxLength: 40,
          style: TextStyle(color: _pal.text, fontSize: 14.5),
          decoration: InputDecoration(
            hintText: 'What should we call you?',
            hintStyle: TextStyle(color: _pal.textDim, fontSize: 13.5),
            filled: true,
            fillColor: _pal.field,
            counterStyle: TextStyle(color: _pal.textDim, fontSize: 10),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: _pal.textDim)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _pal.amber,
              foregroundColor: _pal.onAmber,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    try {
      final updated = await api.updateMe({'display_name': value});
      if (!mounted) return;
      setState(() => _me = updated);
      AppRefresh.instance.requestRefresh();
      _toast(context, 'Name updated');
    } catch (_) {
      if (mounted) _toast(context, 'Could not update name');
    }
  }

  Future<void> _changeAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await api.uploadAvatar(picked.path);
      if (mounted) {
        setState(() => _me = updated);
        AppRefresh.instance.requestRefresh();
      }
      if (mounted) _toast(context, 'Profile image updated.');
    } catch (_) {
      if (mounted) _toast(context, 'Could not upload profile image.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _pal.cardHi,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Log out of MURA?',
            style: TextStyle(
                color: _pal.text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('Your streaks stay safe on the server.',
            style: TextStyle(color: _pal.textDim, fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: _pal.textDim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Log out',
                  style:
                      TextStyle(color: _pal.coral, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loggingOut = true);
    try {
      await api.logout();
    } catch (_) {
      // Even if the server call fails, drop local credentials and move on.
    }
    if (!mounted) return;
    setState(() => _loggingOut = false);
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (final r) => false);
  }

  Future<void> _chooseThemeMode() async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: _pal.cardHi,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ThemeMode.values
              .map(
                (mode) => ListTile(
                  leading: Icon(
                    mode == ThemeMode.light
                        ? Icons.light_mode_outlined
                        : mode == ThemeMode.dark
                            ? Icons.dark_mode_outlined
                            : Icons.brightness_auto_outlined,
                    color: _pal.amber,
                  ),
                  title: Text(
                      mode.name[0].toUpperCase() + mode.name.substring(1),
                      style: TextStyle(color: _pal.text)),
                  trailing: muraThemeMode.value == mode
                      ? Icon(Icons.check, color: _pal.amber)
                      : null,
                  onTap: () => Navigator.pop(context, mode),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected != null) await setMuraThemeMode(selected);
  }

  // ----- build -----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: _pal.amber,
          backgroundColor: _pal.cardHi,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            children: [
              _headerRow(),
              const SizedBox(height: 10),
              FadeSlideIn(index: 0, child: _buildHeroCard()),
              const SizedBox(height: 14),
              FadeSlideIn(index: 1, child: _buildStatsCard()),
              const SizedBox(height: 14),
              FadeSlideIn(index: 2, child: _buildAchievementsCard()),
              const SizedBox(height: 14),
              FadeSlideIn(index: 3, child: _buildActionsCard()),
              const SizedBox(height: 14),
              FadeSlideIn(index: 4, child: _buildAboutCard()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: _pal.text, size: 22),
          tooltip: 'Back',
        ),
        Text('PROFILE',
            style: TextStyle(
                color: _pal.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5)),
      ],
    );
  }

  Widget _buildHeroCard() {
    if (_busy && _me == null) {
      return MuraCard(
        child: SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator(color: _pal.amber)),
        ),
      );
    }
    if (_err != null && _me == null) {
      return MuraCard(
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, color: _pal.textDim, size: 32),
            const SizedBox(height: 10),
            Text('Could not load profile: ${_err!}',
                textAlign: TextAlign.center,
                style: TextStyle(color: _pal.textDim, fontSize: 12)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _pal.amber)),
              child: Text('Retry', style: TextStyle(color: _pal.amber)),
            ),
          ],
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final isPremium = _me?.plan == 'premium';
    return MuraCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Pressable(
            onTap: _changeAvatar,
            child: _RingAvatar(
              avatarUrl: _me?.avatar == null ? null : api.getMediaUrl(_me!.avatar),
              initial: _initial,
            ),
          ),
          const SizedBox(height: 14),
          Text(_name,
              style: TextStyle(
                  color: _pal.text, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('@${_me?.username ?? ""}',
              style: TextStyle(color: _pal.textDim, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPremium
                      ? _pal.amber.withValues(alpha: .16)
                      : _pal.field,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isPremium ? _pal.amber : _pal.stroke,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPremium
                          ? Icons.workspace_premium_rounded
                          : Icons.person_rounded,
                      size: 13,
                      color: isPremium ? _pal.amber : _pal.textDim,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isPremium ? 'PREMIUM' : 'FREE PLAN',
                      style: TextStyle(
                          color: isPremium ? _pal.amber : _pal.textDim,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('Member since $_joined',
                  style: TextStyle(color: _pal.textDim, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _changeAvatar,
            icon: Icon(Icons.photo_camera_outlined,
                size: 16, color: scheme.primary),
            label: Text('Change profile image',
                style: TextStyle(color: scheme.primary)),
            style: TextButton.styleFrom(foregroundColor: scheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return MuraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DISCIPLINE',
              style: TextStyle(
                  color: _pal.textDim,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              StatChip(
                  icon: Icons.local_fire_department_rounded,
                  value: _bestStreak,
                  label: 'Best streak'),
              StatChip(
                  icon: Icons.checklist_rounded,
                  value: _activeHabits,
                  label: 'Habits'),
              StatChip(
                  icon: Icons.book_rounded,
                  value: _journalCount,
                  label: 'Journals'),
              StatChip(
                  icon: Icons.verified_rounded,
                  value: _goalsAchieved,
                  label: 'Goals won'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsCard() {
    final earned = _achievements.where((a) => a.earned).length;
    return MuraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ACHIEVEMENTS',
                  style: TextStyle(
                      color: _pal.textDim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
              const Spacer(),
              Text('$earned / ${_achievements.length}',
                  style: TextStyle(
                      color: _pal.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _achievements
                .map((a) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: a.earned
                            ? _pal.amber.withValues(alpha: .13)
                            : _pal.field,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: a.earned
                                ? _pal.amber.withValues(alpha: .4)
                                : _pal.stroke),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(a.icon,
                              size: 13,
                              color:
                                  a.earned ? _pal.amber : _pal.textDim),
                          const SizedBox(width: 5),
                          Text(a.label,
                              style: TextStyle(
                                  color: a.earned
                                      ? _pal.amber
                                      : _pal.textDim,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return MuraCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _actionTile(
            icon: Icons.auto_awesome_rounded,
            label: 'Automations',
            sub: 'Your WHEN → THEN rules',
            onTap: _loggingOut ? null : () => Navigator.of(context).pushNamed('/automations'),
          ),
          Divider(height: 1, thickness: 1, color: _pal.stroke, indent: 54),
          _actionTile(
            icon: Icons.badge_outlined,
            label: 'Edit display name',
            sub: (_me?.displayName ?? '').trim().isNotEmpty
                ? _me!.displayName
                : 'Not set yet',
            onTap: _loggingOut ? null : _editDisplayName,
          ),
          Divider(height: 1, thickness: 1, color: _pal.stroke, indent: 54),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: muraThemeMode,
            builder: (context, mode, _) => _actionTile(
              icon: mode == ThemeMode.light
                  ? Icons.light_mode_outlined
                  : mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : Icons.brightness_auto_outlined,
              label: 'Appearance',
              sub: mode.name[0].toUpperCase() + mode.name.substring(1),
              onTap: _loggingOut ? null : _chooseThemeMode,
            ),
          ),
          Divider(height: 1, thickness: 1, color: _pal.stroke, indent: 54),
          _actionTile(
            icon: Icons.logout_rounded,
            label: 'Log out',
            sub: _me?.username ?? '',
            tint: _pal.coral,
            trailing: _loggingOut
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _pal.coral))
                : null,
            onTap: _loggingOut ? null : _logout,
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required String sub,
    Color? tint,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tint ?? _pal.amber),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: tint ?? _pal.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _pal.textDim, fontSize: 11)),
                ],
              ),
            ),
            trailing ??
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: _pal.textDim.withValues(alpha: .6)),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard() {
    return MuraCard(
      child: Column(
        children: [
          Text('MURA — build with discipline',
              style: TextStyle(
                  color: _pal.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            _version.isEmpty ? 'v1.4.0' : 'v$_version — obsidian & amber',
            style:
                TextStyle(color: _pal.textDim.withValues(alpha: .6), fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

/// Avatar inside a slowly-pulsing amber ring; the image cross-fades when
/// a new one is uploaded.
class _RingAvatar extends StatefulWidget {
  const _RingAvatar({required this.avatarUrl, required this.initial});

  final String? avatarUrl;
  final String initial;

  @override
  State<_RingAvatar> createState() => _RingAvatarState();
}

class _RingAvatarState extends State<_RingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = MuraPalette.of(context);
    final ring = Tween<double>(begin: 2.5, end: 4.0)
        .animate(CurvedAnimation(parent: _breathe, curve: Curves.easeInOut));
    return AnimatedBuilder(
      animation: ring,
      builder: (context, child) => Container(
        width: 104,
        height: 104,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: pal.amber, width: ring.value),
        ),
        child: child,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: widget.avatarUrl == null
            ? CircleAvatar(
                key: const ValueKey<String>('initial'),
                radius: 44,
                backgroundColor: pal.amber,
                child: Text(widget.initial,
                    style: TextStyle(
                        color: pal.onAmber,
                        fontSize: 34,
                        fontWeight: FontWeight.w800)),
              )
            : CircleAvatar(
                key: ValueKey<String>(widget.avatarUrl!),
                radius: 44,
                backgroundColor: pal.amber,
                child: ClipOval(
                  child: Image.network(
                    widget.avatarUrl!,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Text(widget.initial,
                        style: TextStyle(
                            color: pal.onAmber,
                            fontSize: 34,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
      ),
    );
  }
}
