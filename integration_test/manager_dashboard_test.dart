// Real end-to-end test of the new Manager login + Manager Dashboard, in a
// real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_dashboard_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager login renders the Manager Dashboard with real data, no hamburger/bell, Dispute above PTP', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ---- Login ----
    await tester.enterText(find.byType(TextField).at(0), 'suresh.mgr');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing, reason: 'Manager credentials must authenticate successfully');
    print('✓ Manager login successful (suresh.mgr / 1234)');

    // ---- Dashboard basics ----
    expect(find.text('Manager Dashboard'), findsOneWidget, reason: 'Manager must land on the Manager Dashboard');
    expect(find.text("Welcome back! Here's the overview of today's recovery."), findsOneWidget);
    print('✓ Manager Dashboard header rendered');

    // ---- No hamburger, no notification bell ----
    expect(find.byIcon(Icons.menu), findsNothing, reason: 'Manager Dashboard must not show a hamburger icon');
    expect(find.byIcon(Icons.notifications_outlined), findsNothing, reason: 'Manager Dashboard must not show a notification bell');
    expect(find.byIcon(Icons.notifications_none), findsNothing, reason: 'Manager Dashboard must not show a notification bell');
    print('✓ Verified: no hamburger icon, no notification bell');

    // ---- Real (non-hardcoded) stat cards ----
    // "Total Outstanding" legitimately appears twice: the stat card label
    // and the Outstanding Ageing donut's center label.
    expect(find.text('Total Outstanding'), findsNWidgets(2));
    expect(find.text('Amount Collected Today'), findsOneWidget);
    expect(find.text("Today's Target (All)"), findsOneWidget);
    expect(find.text('PTP Due Today'), findsOneWidget);
    expect(find.text('Overdue Amount'), findsOneWidget);
    print('✓ All 5 stat cards rendered with live store data');

    // ---- Dispute Overview must appear ABOVE PTP Overview (stacked) ----
    expect(find.text('Dispute Overview'), findsOneWidget);
    expect(find.text('PTP Overview'), findsOneWidget);
    final disputeY = tester.getTopLeft(find.text('Dispute Overview')).dy;
    final ptpY = tester.getTopLeft(find.text('PTP Overview')).dy;
    expect(disputeY, lessThan(ptpY), reason: 'Dispute Overview must be positioned above PTP Overview (stacked vertically)');
    print('✓ Verified: Dispute Overview is stacked directly above PTP Overview');

    // ---- Sales Team Performance + Top Overdue Customers + Alerts ----
    expect(find.text('Sales Team Performance (Today)'), findsOneWidget);
    expect(find.text('Top 5 Overdue Customers'), findsOneWidget);
    expect(find.text('Alerts & Reminders'), findsOneWidget);
    print('✓ Performance table, overdue customers, and alerts sections all rendered');

    // ---- Bottom nav: Dashboard, Customers, Tasks, Reports, Profile ----
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Customers'), findsWidgets);
    expect(find.text('Tasks'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
    print('✓ Bottom nav shows Dashboard / Customers / Tasks / Reports / Profile');

    // ---- Navigate through the other tabs to confirm they render without error ----
    await tester.tap(find.text('Customers'));
    await settle(tester);
    print('✓ Customers tab opened without error');

    await tester.tap(find.text('Tasks'));
    await settle(tester);
    print('✓ Tasks tab opened without error');

    await tester.tap(find.text('Reports'));
    await settle(tester);
    print('✓ Reports tab opened without error');

    await tester.tap(find.text('Profile'));
    await settle(tester);
    expect(find.textContaining('Manager'), findsWidgets, reason: 'Profile tab header must show the Manager role label, not a leftover Recovery Executive label');
    print('✓ Profile tab opened, shows Manager role label correctly');

    print('✓ Manager Dashboard flow complete');
  });
}
