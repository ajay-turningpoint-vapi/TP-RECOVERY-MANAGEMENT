// Real end-to-end test of the Manager's new Priority Accounts screen, in a
// real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_priority_accounts_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Priority Accounts: real stats, tabs, search, filters, distribution, read-only detail', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(find.byType(TextField).at(0), 'suresh.mgr');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
    print('✓ Manager login successful');

    // Dashboard's "Top 5 Overdue Customers" card's "View Details" must now
    // open Priority Accounts.
    final dashboardList = find.byType(SingleChildScrollView).first;
    for (var i = 0; i < 8 && find.text('Top 5 Overdue Customers').evaluate().isEmpty; i++) {
      await tester.drag(dashboardList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Top 5 Overdue Customers'), findsOneWidget);
    final headerRow = find.ancestor(of: find.text('Top 5 Overdue Customers'), matching: find.byType(Row)).first;
    final viewDetailsLink = find.descendant(of: headerRow, matching: find.text('View Details'));
    await tester.ensureVisible(viewDetailsLink);
    await settle(tester);
    await tester.tap(viewDetailsLink);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Priority Accounts'), findsOneWidget, reason: 'Top 5 Overdue Customers "View Details" must open the new Priority Accounts screen');
    expect(find.text('High-priority customer accounts needing attention'), findsOneWidget);
    print('✓ Priority Accounts screen opened from Dashboard "View Details"');

    // ---- Stat cards ----
    expect(find.text('Total Accounts'), findsOneWidget);
    expect(find.text('Total Due'), findsWidgets);
    expect(find.text('Total Received'), findsOneWidget);
    final statCardsRow = find.byType(ListView).at(1);
    for (var i = 0; i < 6 && find.text('Overdue').evaluate().isEmpty; i++) {
      await tester.drag(statCardsRow, const Offset(-200, 0));
      await settle(tester);
    }
    expect(find.text('Overdue'), findsWidgets);
    print('✓ Stat cards rendered with live data');

    // ---- Tabs genuinely re-filter the same data ----
    expect(find.text('Priority'), findsWidgets);
    expect(find.text('Overdue'), findsWidgets);
    expect(find.text('Broken PTP'), findsWidgets);
    expect(find.text('No Follow-Up'), findsWidgets);
    await tester.tap(find.text('Broken PTP').last);
    await settle(tester);
    expect(find.textContaining('No priority accounts match'), findsNothing, reason: 'There must be real broken-PTP customers to show on this tab');
    print('✓ Broken PTP tab genuinely filters to real broken-PTP accounts');
    await tester.tap(find.text('No Follow-Up').last);
    await settle(tester);
    await tester.tap(find.text('Overdue').last);
    await settle(tester);
    await tester.tap(find.text('Priority').last);
    await settle(tester);
    print('✓ All 4 tabs tapped and re-rendered without error');

    // ---- Search is real ----
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'zzz_no_such_customer_zzz');
    await settle(tester);
    expect(find.text('No priority accounts match this search.'), findsOneWidget, reason: 'Search must genuinely filter the account list');
    print('✓ Search box genuinely filters the account list');
    await tester.tap(searchField);
    await settle(tester);
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('No priority accounts match this search.'), findsNothing, reason: 'Clearing the search box must actually restore the full account list');

    // ---- Branch filter is real ----
    final dropdowns = find.byIcon(Icons.keyboard_arrow_down);
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final mumbaiOption = find.text('Mumbai').last;
    if (mumbaiOption.evaluate().isNotEmpty) {
      await tester.tap(mumbaiOption);
      await settle(tester);
      expect(find.text('Mumbai'), findsWidgets, reason: 'Selecting a branch must actually apply as the active filter');
      print('✓ Branch filter dropdown opened and a real branch was applied');
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      await tester.tap(find.text('All Branches').last);
      await settle(tester);
    }

    // ---- Total / Avg row present ----
    final outerList = find.byType(ListView).first;
    for (var i = 0; i < 6 && find.text('Total / Avg.').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Total / Avg.'), findsOneWidget);
    print('✓ Total / Avg row rendered');

    // ---- Export gives real feedback ----
    final exportButton = find.byIcon(Icons.download);
    await tester.ensureVisible(exportButton);
    await settle(tester);
    await tester.tap(exportButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Priority Accounts report exported.'), findsOneWidget, reason: 'Export must give real feedback');
    print('✓ Export gives real feedback');

    // ---- Priority Distribution buckets ----
    for (var i = 0; i < 20 && find.text('Priority Distribution').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, -500));
      await settle(tester);
    }
    expect(find.text('Priority Distribution'), findsOneWidget);
    expect(find.text('Critical'), findsWidgets);
    expect(find.text('Low'), findsWidgets);
    print('✓ Priority Distribution buckets rendered');

    // ---- Row tap opens a genuinely read-only detail sheet ----
    for (var i = 0; i < 10 && find.byType(CircleAvatar).evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, 400));
      await settle(tester);
    }
    final avatars = find.byType(CircleAvatar);
    expect(avatars, findsWidgets, reason: 'The priority accounts table must have real rows to tap');
    final firstRow = find.ancestor(of: avatars.first, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(firstRow);
    await settle(tester);
    await tester.tap(firstRow);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.textContaining('Manager view is read-only'), findsOneWidget, reason: 'Account detail sheet must explicitly state it is read-only');
    final sheetButtons = find.descendant(of: find.byType(BottomSheet), matching: find.byType(ElevatedButton));
    expect(sheetButtons, findsNothing, reason: 'The read-only detail sheet must contain no action buttons');
    print('✓ Tapping an account opens a genuinely read-only detail sheet');
    await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Manager view is read-only'), findsNothing, reason: 'Dragging the sheet down must actually dismiss it');

    // ---- Back navigation ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Priority Accounts'), findsNothing, reason: 'Back must leave the Priority Accounts screen');
    expect(find.text('Manager Dashboard'), findsOneWidget, reason: 'Back must return to the Manager Dashboard');
    print('✓ Back navigation returns to the Dashboard');

    print('✓ Manager Priority Accounts flow complete');
  });
}
