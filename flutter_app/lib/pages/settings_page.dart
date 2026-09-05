/// MURA — Settings page: profile, display-name edit, notification placeholder,
/// and logout (clears stored tokens via the API client, then routes to /login).
///
/// Assumes the shared api singleton from ../api.dart exposes:
///   me() -> UserProfile
///   updateMe(Map`<String, dynamic`>) -> UserProfile
///   logout() -> Future`<void`>   // clears secure storage / JWT tokens
/// And ../models.dart type:
///   UserProfile {username, email, firstName, displayName, dateJoined}
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../models.dart';
import '../refresh_bus.dart';
import '../theme.dart'; // ignore: unused_import

// Obsidian & Amber palette (#0D0B09 family backgrounds, amber accents).

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

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2A2117),
      content: Text(msg, style: TextStyle(color: MuraPalette.of(context).text)),
    ));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  MuraPalette get _pal => MuraPalette.of(context);
  UserProfile? _me;
  bool _busy = false;
  String? _err;
  bool _notifications = true;
  bool _loggingOut = false;

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
      final profile = await api.me();
      if (!mounted) return;
      setState(() {
        _me = profile;
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

  String get _name {
    final dn = (_me?.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    return _me?.username ?? '';
  }

  String get _initial {
    final n = _name.trim();
    return n.isEmpty ? 'B' : n[0].toUpperCase();
  }

  String _joined(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${_months[d.month - 1]} ${d.year}';
  }

  Future<void> _editDisplayName() async {
    final ctrl = TextEditingController(text: _me?.displayName ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B140D),
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
        backgroundColor: const Color(0xFF1B140D),
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
      await api.logout(); // clears tokens / secure storage inside the client
    } catch (_) {
      // Even if the server call fails, drop local credentials and move on.
    }
    if (!mounted) return;
    setState(() => _loggingOut = false);
    // Requires the '/login' route registered in main.dart (owned elsewhere).
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (final r) => false);
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(100),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: _pal.amber,
          backgroundColor: _pal.field,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 48),
            children: [
              const SizedBox(height: 14),
              _buildProfileCard(),
              const SizedBox(height: 14),
              _buildActionsCard(),
              const SizedBox(height: 14),
              _buildAboutCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    if (_busy && _me == null) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: _cardDeco(),
        child: CircularProgressIndicator(color: _pal.amber),
      );
    }
    if (_err != null && _me == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: _cardDeco(),
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
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_pal.card, Color(0xFF241C12)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _pal.stroke),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _changeAvatar,
            child: CircleAvatar(
              radius: 36,
              backgroundColor: _pal.amber,
              backgroundImage:
                  _me?.avatar == null ? null : NetworkImage(_me!.avatar!),
              child: _me?.avatar == null
                  ? Text(_initial,
                      style: TextStyle(
                          color: _pal.onAmber,
                          fontSize: 30,
                          fontWeight: FontWeight.w800))
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          Text(_name,
              style: TextStyle(
                  color: _pal.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${_me?.username ?? ""}  |  ${_me?.email ?? ""}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _pal.textDim, fontSize: 12.5)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _changeAvatar,
            icon: const Icon(Icons.photo_camera_outlined, size: 17),
            label: const Text('Change profile image'),
            style: TextButton.styleFrom(foregroundColor: _pal.amber),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_rounded,
                  size: 12, color: _pal.amber.withValues(alpha: .8)),
              const SizedBox(width: 5),
              Text('Member since ${_joined(_me?.dateJoined)}',
                  style: TextStyle(color: _pal.textDim, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDeco(),
      child: Column(
        children: [
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _pal.field,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.notifications_none_rounded,
                      size: 18, color: _pal.amber),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notifications',
                          style: TextStyle(
                              color: _pal.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('Pushed to your devices via Signo when due',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _pal.textDim, fontSize: 11)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _notifications,
                  activeThumbColor: _pal.amber,
                  activeTrackColor: _pal.amber.withValues(alpha: 0.4),
                  onChanged: _loggingOut
                      ? null
                      : (v) => setState(() => _notifications = v),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: _pal.stroke, indent: 54),
          _actionTile(
            icon: Icons.logout_rounded,
            label: 'Log out',
            sub: _me?.username ?? "",
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

  Future<void> _chooseThemeMode() async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
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
                  ),
                  title:
                      Text(mode.name[0].toUpperCase() + mode.name.substring(1)),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(),
      child: Column(
        children: [
          Text('MURA - build with discipline',
              style: TextStyle(
                  color: _pal.textDim, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('v1.0.0 - obsidian & amber',
              style: TextStyle(
                  color: _pal.textDim.withValues(alpha: .6), fontSize: 10.5)),
        ],
      ),
    );
  }
}
