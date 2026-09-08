import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'onboarding_flow.dart';
import 'pages/automations_page.dart';
import 'pages/habits_page.dart';
import 'pages/journal_page.dart';
import 'pages/library_page.dart';
import 'pages/plan_page.dart';
import 'pages/profile_page.dart';
import 'pages/today_page.dart';
import 'pages/wealth_page.dart';
import 'push_service.dart';
import 'refresh_bus.dart';
import 'theme.dart';
import 'updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Surface every uncaught Dart error (with stack) in the log under [MURA]
  // so device-side failures are diagnosable via adb logcat (debug only;
  // release builds keep the console clean).
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[MURA] UI-ERROR ${details.exception}\n${details.stack}');
    }
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[MURA] UNCAUGHT $error\n$stack');
    }
    return true;
  };
  // Firebase/local notifications. Failures (no Play services, no config)
  // disable push only — the in-app feed still works.
  await initPush();
  await loadMuraThemeMode();
  runApp(const MuraApp());
}

/// Root widget. Restores any stored session BEFORE building the navigator so
/// the auth gate can decide between '/' (the tab shell) and '/login'. While
/// the check runs, a themed splash is shown instead of a white flash.
class MuraApp extends StatefulWidget {
  const MuraApp({super.key});

  @override
  State<MuraApp> createState() => _MuraAppState();
}

class _MuraAppState extends State<MuraApp> {
  bool _restoring = true;
  bool _hasToken = false;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.sessionEpoch.addListener(_handleSessionEpoch);
    _restoreSession();
  }

  @override
  void dispose() {
    ApiClient.instance.sessionEpoch.removeListener(_handleSessionEpoch);
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final bool hasToken = await ApiClient.instance.hasToken();
    if (!mounted) return;
    setState(() {
      _hasToken = hasToken;
      _restoring = false;
    });
    if (hasToken) {
      // Re-register this device for pushes (idempotent upsert) so token
      // rotation never silently stops delivery on an already-signed-in user.
      unawaited(registerForPush());
      // When a signed-in user reaches the shell, quietly check whether a newer
      // build was published and offer the in-app update.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(seconds: 3), maybePromptForUpdate);
      });
    }
    // If an update was downloading in the background (system DownloadManager)
    // and finished while the app was closed, offer to finish the install.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 5), maybeFinishPendingUpdate);
    });
  }

  /// The API client bumps [ApiClient.sessionEpoch] whenever a refresh fails
  /// and tokens are wiped; drop back to the login gate.
  void _handleSessionEpoch() {
    if (!mounted) return;
    setState(() => _hasToken = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget homeWidget;
    if (_restoring) {
      homeWidget = const Scaffold(
        backgroundColor: MuraColors.background,
        body: Center(
          child: CircularProgressIndicator(color: MuraColors.primary),
        ),
      );
    } else if (_hasToken) {
      homeWidget = HomeShell();
      unawaited(registerForPush());
    } else {
      homeWidget = OnboardingFlow(
        authEnabled: true,
        onFinished: () {
          if (!mounted) return;
          unawaited(registerForPush());
          setState(() {
            _hasToken = true;
          });
        },
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: muraThemeMode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'MURA',
        debugShowCheckedModeBanner: false,
        theme: buildMuraLightTheme(),
        darkTheme: buildMuraTheme(),
        themeMode: themeMode,
        navigatorKey: muraNavigatorKey,
        builder: (context, child) {
          ErrorWidget.builder = (details) => _MuraErrorWidget(details);
          return child ?? const _MuraErrorWidget(null);
        },
        // Replacing the auth gate directly avoids keeping an outgoing
        // inherited-widget tree alive while the shell is mounting.
        home: homeWidget,
        routes: <String, WidgetBuilder>{
          '/login': (_) => OnboardingFlow(
                authEnabled: true,
                onFinished: () {
                  if (!mounted) return;
                  unawaited(registerForPush());
                  setState(() {
                    _hasToken = true;
                  });
                },
              ),
          '/home': (_) => HomeShell(),
          '/settings': (_) => const ProfilePage(),
          '/automations': (_) => const AutomationsPage(),
        },
      ),
    );
  }
}

class _MuraErrorWidget extends StatelessWidget {
  const _MuraErrorWidget(this.details);

  final FlutterErrorDetails? details;

  @override
  Widget build(BuildContext context) {
    // Raw exception text is logged for diagnosis, never shown to the user.
    if (details != null && kDebugMode) {
      // ignore: avoid_print
      print('[MURA] RENDER-ERROR '
          '${details!.exception}\n'
          '${details!.stack}');
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'MURA could not render this screen. Please try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

/// Titles shown in the top bar for each tab.
const List<String> _kTabTitles = <String>[
  'Today',
  'Habits',
  'Goals',
  'Wealth',
  'Journal',
  'Library',
];

/// Persistent app shell: glass top bar (logo + screen title, notification
/// bell, profile avatar) over an [IndexedStack] of the five primary tabs,
/// with a themed bottom [NavigationBar]. Settings lives behind the avatar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _unread = 0;
  User? _user;

  late final List<Widget> _pages = <Widget>[
    TodayPage(),
    HabitsPage(),
    PlanPage(),
    WealthPage(),
    JournalPage(),
    LibraryPage(),
  ];

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.wb_sunny_outlined),
      selectedIcon: Icon(Icons.wb_sunny_rounded),
      label: 'Today',
    ),
    NavigationDestination(
      icon: Icon(Icons.local_fire_department_outlined),
      selectedIcon: Icon(Icons.local_fire_department_rounded),
      label: 'Habits',
    ),
    NavigationDestination(
      icon: Icon(Icons.flag_outlined),
      selectedIcon: Icon(Icons.flag_rounded),
      label: 'Goals',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_balance_wallet_outlined),
      selectedIcon: Icon(Icons.account_balance_wallet_rounded),
      label: 'Wealth',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book_rounded),
      label: 'Journal',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_stories_outlined),
      selectedIcon: Icon(Icons.auto_stories_rounded),
      label: 'Library',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshUnread();
    _refreshUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Fresh data whenever the user comes back to the app.
    if (state == AppLifecycleState.resumed) {
      AppRefresh.instance.requestRefresh();
      _refreshUnread();
      _refreshUser();
    }
  }

  Future<void> _refreshUser() async {
    try {
      final user = await api.me();
      if (mounted) setState(() => _user = user);
    } catch (_) {}
  }

  Future<void> _refreshUnread() async {
    try {
      final List<AppNotification> items = await api.notifications();
      if (!mounted) return;
      setState(() =>
          _unread = items.where((AppNotification n) => n.isUnread).length);
    } catch (_) {
      // Badge is best-effort; never block the shell on it.
    }
  }

  void _onDestinationSelected(int index) {
    setState(() => _tab = index);
    // Dynamic refresh: the newly visible tab silently reloads its data.
    AppRefresh.instance.requestRefresh();
  }

  Future<void> _openNotifications() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B140D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) => const _NotificationsSheet(),
    );
    if (mounted) _refreshUnread();
  }

  void _openProfile() {
    Navigator.of(context).pushNamed('/settings');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: <Widget>[
          _TopBar(
            title: _kTabTitles[_tab],
            unread: _unread,
            onNotifications: _openNotifications,
            onProfile: _openProfile,
            avatar: _user?.avatar,
            initials: _user?.effectiveName,
          ),
          Expanded(
            // IndexedStack keeps every tab's state alive (scroll position,
            // loaded data) instead of remounting on each switch — switching
            // is now instant, and the AnimatedSwitcher cross-fades the top
            // bar title.
            child: IndexedStack(
              index: _tab,
              children: _pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            selectedIndex: _tab,
            destinations: _destinations,
            onDestinationSelected: _onDestinationSelected,
          ),
        ),
      ),
    );
  }
}

/// Glass app bar shared by every tab: flame mark + screen title on the
/// left, notification bell (with unread badge) and profile avatar on the
/// right. The avatar opens Settings, keeping the bottom bar to five tabs.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.unread,
    required this.onNotifications,
    required this.onProfile,
    this.avatar,
    this.initials,
  });

  final String title;
  final int unread;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;
  final String? avatar;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withAlpha(235),
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                Icon(Icons.local_fire_department_rounded,
                    color: scheme.primary, size: 24),
                const SizedBox(width: 10),
                // Soft cross-fade between tab titles (the pages persist in
                // the IndexedStack below, so only the label changes).
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    title,
                    key: ValueKey<String>(title),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const Spacer(),
                _BellButton(unread: unread, onTap: onNotifications),
                const SizedBox(width: 10),
                _AvatarButton(
                    onTap: onProfile, avatar: avatar, initials: initials),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        IconButton(
          onPressed: onTap,
          icon: Icon(Icons.notifications_outlined,
              color: scheme.onSurfaceVariant, size: 24),
          tooltip: 'Notifications',
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFF131313), width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF131313),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.onTap, this.avatar, this.initials});

  final VoidCallback onTap;
  final String? avatar;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    final String label = (initials ?? 'M').substring(0, 1).toUpperCase();
    final bool hasAvatar = avatar != null && avatar!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFFC174),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        // Image.network with graceful fallbacks replaces DecorationImage so
        // broken or offline avatars degrade to the initial, not an exception.
        child: hasAvatar
            ? ClipOval(
                child: Image.network(
                  ApiClient.instance.getMediaUrl(avatar),
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _avatarFallback(label),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : _avatarFallback(label),
                ),
              )
            : _avatarFallback(label),
      ),
    );
  }

  Widget _avatarFallback(String label) => Container(
        width: 34,
        height: 34,
        color: const Color(0xFFFFC174),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2A1700),
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

/// Bottom sheet listing the pushed-event feed; marks everything read.
class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet();

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  List<AppNotification>? _items;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<AppNotification> items = await api.notifications();
      if (!mounted) return;
      setState(() => _items = items);
      await api.markAllNotificationsRead();
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 430,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                'Notifications',
                style: TextStyle(
                  color: Color(0xFFE5E2E1),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Divider(color: Color(0xFF2A2015), height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_err != null) {
      return const Center(
        child: Text(
          'Could not load notifications',
          style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 13),
        ),
      );
    }
    final List<AppNotification>? items = _items;
    if (items == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFC174)),
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.notifications_none_rounded,
                  color: Color(0xFF6E6052), size: 40),
              SizedBox(height: 10),
              Text(
                'Nothing yet',
                style: TextStyle(color: Color(0xFFA79B8A), fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                'Reminders, streaks and wins land here.',
                style: TextStyle(color: Color(0xFF6E6052), fontSize: 12.5),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Color(0xFF241B10), height: 1, indent: 66),
      itemBuilder: (BuildContext context, int i) {
        final AppNotification n = items[i];
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2015),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(n.icon, color: const Color(0xFFFFC174), size: 20),
          ),
          title: Text(
            n.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFE5E2E1),
              fontSize: 14.5,
              fontWeight: n.isUnread ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          subtitle: n.body.isEmpty
              ? null
              : Text(
                  n.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFFA79B8A), fontSize: 12.5),
                ),
          trailing: n.isUnread
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFC174),
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        );
      },
    );
  }
}
