// Verifies RE and Manager screens show real, correctly-scoped, internally
// consistent counts/amounts — the same class of bug already found and fixed
// on the salesperson Dashboard (company-wide numbers leaking into a
// scoped view) and on the Manager Dashboard's "No follow-up accounts"
// alert (badge count computed from a different metric than the screen it
// navigates to).
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/re_manager_counts_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  Future<void> login(WidgetTester tester, String username, String password) async {
    await tester.enterText(find.byType(TextField).at(0), username);
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), password);
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
  }

  testWidgets('RE and Manager dashboards show real, consistent counts', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= RE: Control Dashboard =================
    await login(tester, 'amit.re', '1234');
    // The RE Control Dashboard is the landing screen after login.
    expect(find.textContaining('₹'), findsWidgets, reason: 'RE Control Dashboard must show real ₹ figures, not blank/zero');
    // Company-wide total overdue across the curated dataset (5 customers,
    // 3 Rahul's + 2 Mahesh's: 4L+3L+45K+7.5L+60K = ₹15,55,000), formatted
    // via NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).
    expect(find.textContaining('₹15,55,000'), findsWidgets, reason: 'RE Control Dashboard "Total Overdue" must reflect the real company-wide ₹15,55,000 across all 5 curated customers');
    print('✓ RE Control Dashboard "Total Overdue" shows the real company-wide ₹15,55,000');

    expect(find.textContaining('Needs Your Attention'), findsWidgets, reason: 'RE Control Dashboard must show the Needs Your Attention section');
    print('✓ RE Control Dashboard shows the Needs Your Attention section');

    // The red badge next to "Needs Your Attention" must equal the sum of the
    // 4 tiles actually shown below it — this is the exact bug that was just
    // fixed (the badge used to also fold in 3 categories that only appear
    // after tapping "View All", inflating it beyond what's visible here).
    final store = Provider.of<AppStore>(tester.element(find.byType(Scaffold).first), listen: false);
    final expectedVisibleAttentionCount = store.salesmenNoCallTodayCount + store.salesmenOverdueTargetsCount + store.physicalVisitsPendingReviewCount + store.disputesAwaitingReviewCount;
    final headerRow = find.ancestor(of: find.text('Needs Your Attention'), matching: find.byType(Row)).first;
    final headerTexts = find.descendant(of: headerRow, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
    final badgeText = headerTexts.firstWhere((t) => RegExp(r'^\d+$').hasMatch(t), orElse: () => '');
    expect(badgeText, isNotEmpty, reason: 'Could not read the numeric badge next to "Needs Your Attention"');
    expect(badgeText, equals('$expectedVisibleAttentionCount'), reason: 'The badge must equal the sum of the 4 visible tiles (No Call Today + Overdue Targets + Visits Pending Review + Disputes), not a larger total that includes categories not shown here');
    print('✓ RE Control Dashboard "Needs Your Attention" badge ($badgeText) matches the sum of the 4 visible tiles');

    // ================= Logout, then Manager =================
    // Icons.person_outline can also appear as a plain content icon elsewhere
    // on the dashboard (unrelated to the bottom-nav Profile tab), so scope
    // the tap to the actual BottomNavigationBar.
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.person_outline)));
    await settle(tester);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.text('Logout'), findsOneWidget, reason: 'Profile screen must show a real Logout control');
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await login(tester, 'suresh.mgr', '1234');
    expect(find.textContaining('₹'), findsWidgets, reason: 'Manager Dashboard must show real ₹ figures');
    print('✓ Manager Dashboard renders with real ₹ figures');

    // The "No follow-up accounts" alert row must navigate to a screen whose
    // own tile shows the SAME count — this is the exact bug that was just
    // fixed (the row previously showed an unrelated "zero calls today"
    // metric that disagreed with the destination screen).
    expect(find.text('No follow-up accounts'), findsOneWidget);
    final alertRow = find.ancestor(of: find.text('No follow-up accounts'), matching: find.byType(InkWell)).first;
    await tester.ensureVisible(alertRow);
    await settle(tester);
    // Read the count shown next to the row before navigating away.
    final countFinder = find.descendant(
      of: find.ancestor(of: find.text('No follow-up accounts'), matching: find.byType(Row)).first,
      matching: find.byType(Text),
    );
    final rowTexts = countFinder.evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
    final dashboardCount = rowTexts.firstWhere((t) => RegExp(r'^\d+$').hasMatch(t), orElse: () => '');
    expect(dashboardCount, isNotEmpty, reason: 'Could not read the numeric count next to "No follow-up accounts" on the Manager Dashboard');

    await tester.tap(alertRow);
    await settle(tester);
    expect(find.textContaining('No follow-up accounts'), findsWidgets, reason: 'Must navigate to the Alerts & Reminders screen showing the same alert');
    expect(find.text(dashboardCount), findsWidgets, reason: 'The destination screen must show the SAME count the dashboard badge showed — this is the exact bug that was fixed (badge vs. list count mismatch)');
    print('✓ Manager Dashboard "No follow-up accounts" count ($dashboardCount) matches the Alerts & Reminders screen it navigates to');

    print('✓ COMPLETE: RE and Manager dashboards show real, internally consistent data.');
  });
}
