import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mura/main.dart';
import 'package:mura/pages/profile_page.dart';
import 'package:mura/theme.dart';

void main() {
  // Hermetic smoke test for the app shell: no network, no plugins.
  // Pages kick off API loads on init, but every loader catches its own
  // errors and renders an error box, so the shell must stay stable even
  // when all requests fail.

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildMuraTheme(),
        themeMode: ThemeMode.dark,
        home: const HomeShell(),
        routes: <String, WidgetBuilder>{
          '/settings': (_) => const ProfilePage(),
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shell shows the primary tabs and a profile avatar',
      (tester) async {
    await pumpShell(tester);

    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    expect(
        find.descendant(of: bar, matching: find.byType(NavigationDestination)),
        findsNWidgets(6));
    for (final label in <String>[
      'Today',
      'Habits',
      'Goals',
      'Wealth',
      'Journal',
      'Library',
    ]) {
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    // Top bar shows the active tab's title.
    expect(find.text('Today'), findsNWidgets(2)); // nav label + top bar title
    // Settings is NOT a bottom tab anymore; the avatar opens it.
    expect(find.descendant(of: bar, matching: find.text('Settings')),
        findsNothing);
    expect(find.text('M'), findsOneWidget); // avatar initial (falls back to 'M' with no /me/ user)
  });

  testWidgets('tapping a destination switches the visible page',
      (tester) async {
    await pumpShell(tester);

    int stackIndex() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack).first).index!;
    int navIndex() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    expect(stackIndex(), 0);
    expect(navIndex(), 0);

    await tester.tap(find.text('Habits'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(stackIndex(), 1);
    expect(navIndex(), 1);

    await tester.tap(find.text('Goals'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(stackIndex(), 2);
    expect(navIndex(), 2);
  });

  testWidgets('avatar action pushes the Profile page above the shell',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('M')); // profile avatar opens Profile
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Settings route pushed on top of the shell, which stays mounted below.
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
