// Production seed data was deliberately cleared to empty (real customers
// only, no mock/demo data) — this test proves every major screen across all
// 3 roles renders cleanly with ZERO customers/tasks/PTPs/disputes/etc.
// instead of crashing on an unguarded .first/firstWhere(orElse: () =>
// list.first) somewhere. If any screen throws during build, flutter_test
// fails this test automatically (it doesn't need explicit exception
// assertions — an uncaught FlutterError during a pumped frame fails the
// enclosing test).
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/empty_data_smoke_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  // ensureVisible + tap, used for every bottom-nav icon tap in this test —
  // headless Chrome occasionally needs the extra settle/visibility pass
  // before a tap's hit-test geometry resolves reliably.
  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    final finder = find.byIcon(icon).last;
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> login(WidgetTester tester, String username, String password) async {
    await tester.enterText(find.byType(TextField).at(0), username);
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), password);
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
  }

  Future<void> logoutFromProfileTab(WidgetTester tester, IconData profileIcon) async {
    await tapIcon(tester, profileIcon);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.text('Logout'), findsOneWidget);
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsWidgets);
  }

  testWidgets('Every major screen across all 3 roles renders without crashing when all business data is empty', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= SALESPERSON =================
    await login(tester, 'rahul', '1234');
    print('✓ Salesperson login with zero seed data succeeded');

    await tapIcon(tester, Icons.people);
    print('✓ Salesperson Customers tab renders with zero customers');

    await tapIcon(tester, Icons.assignment);
    print('✓ Salesperson Tasks tab renders with zero tasks');

    await logoutFromProfileTab(tester, Icons.person);
    print('✓ Salesperson Profile/Logout renders and works with zero data');

    // ================= RECOVERY EXECUTIVE =================
    await login(tester, 'amit.re', '1234');
    print('✓ Recovery Executive login with zero seed data succeeded');

    await tapIcon(tester, Icons.people_outline);
    print('✓ RE Company Recovery Queue (Customers) renders with zero customers');

    await tapIcon(tester, Icons.assignment_outlined);
    print('✓ RE Tasks tab renders with zero tasks/disputes/ptps');

    await tapIcon(tester, Icons.bar_chart_outlined);
    print('✓ RE Reports landing screen renders with zero data');

    const reportTitles = [
      'Daily Recovery Summary',
      'Salesman Performance Report',
      'PTP Report',
      'Broken PTP Report',
      'Dispute Status Report',
      'Ageing Receivables Report',
      'Expected vs Actual Collection',
      'No Follow-Up Accounts',
    ];
    for (final title in reportTitles) {
      final tile = find.text(title);
      if (tile.evaluate().isEmpty) {
        // Some report tiles may require a scroll to reach.
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await settle(tester);
      }
      expect(tile, findsWidgets, reason: '$title tile must still render on the Reports screen with zero data');
      await tester.ensureVisible(tile.first);
      await settle(tester);
      await tester.tap(tile.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 800));
      print('✓ Report screen "$title" renders with zero data');
      await tester.pageBack();
      await settle(tester);
    }

    // More menu screens — scroll the Reports list back to top first, since
    // the header (with the hamburger icon) can lazily unmount after
    // scrolling down through all 8 report tiles.
    for (var i = 0; i < 10 && find.byIcon(Icons.menu).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, 600));
      await settle(tester);
    }
    await tapIcon(tester, Icons.menu);
    print('✓ RE More menu renders with zero data');

    // BUSY Sync is intentionally hidden once logged in via the real API
    // (see AppStore.refreshBusySync's doc comment) — it's a local-only
    // demo simulator with no real server-side equivalent, so it must not
    // appear here.
    const moreMenuItems = ['Escalations', 'Needs Attention', 'Salesmen', 'Notifications', '5 PM Control'];
    for (final item in moreMenuItems) {
      final tile = find.text(item);
      expect(tile, findsWidgets, reason: '$item tile must still render on the More menu with zero data');
      await tester.ensureVisible(tile.first);
      await settle(tester);
      await tester.tap(tile.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 800));
      print('✓ More-menu screen "$item" renders with zero data');
      await tester.pageBack();
      await settle(tester);
    }

    // Still on MoreMenuScreen itself (pushed from the Reports tab) — one
    // more pop returns to the bottom-nav tab so its icons are in the tree.
    await tester.pageBack();
    await settle(tester);

    await logoutFromProfileTab(tester, Icons.person_outline);
    print('✓ RE Profile/Logout renders and works with zero data');

    // ================= MANAGEMENT =================
    await login(tester, 'suresh.mgr', '1234');
    print('✓ Manager login with zero seed data succeeded');

    // Dashboard is already the default tab (index 0) right after login —
    // no tap needed, and re-tapping an already-selected bottom-nav icon is
    // exactly the flaky pattern seen earlier in this test (icon/activeIcon
    // opacity-crossfade widgets briefly non-hit-testable).
    print('✓ Manager Control Dashboard renders with zero data (stat cards, Needs Attention, Salesmen Performance)');

    await tapIcon(tester, Icons.people_outline);
    print('✓ Manager Customers tab renders with zero customers');

    await tapIcon(tester, Icons.assignment_outlined);
    print('✓ Manager Tasks tab renders with zero tasks');

    await tapIcon(tester, Icons.bar_chart_outlined);
    print('✓ Manager Reports landing screen renders with zero data');

    await tapIcon(tester, Icons.person_outline);
    print('✓ Manager Profile screen renders with zero data');

    print('✓ ALL major screens across Salesperson, RE, and Manager roles render cleanly with zero business data — no crashes.');
  });
}
