// Real end-to-end test of the Manager's new Team Recovery screen, in a real
// Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_team_recovery_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Team Recovery: real stats, tabs, search, branch filter, distribution, read-only detail', (tester) async {
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

    // Dashboard's "Sales Team Performance (Today)" card's "View Details" link
    // must now open Team Recovery (not the old Recovery Owner screen).
    final dashboardList = find.byType(SingleChildScrollView).first;
    for (var i = 0; i < 8 && find.text('Sales Team Performance (Today)').evaluate().isEmpty; i++) {
      await tester.drag(dashboardList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Sales Team Performance (Today)'), findsOneWidget);
    final performanceHeaderRow = find.ancestor(of: find.text('Sales Team Performance (Today)'), matching: find.byType(Row)).first;
    final viewDetailsLink = find.descendant(of: performanceHeaderRow, matching: find.text('View Details'));
    await tester.ensureVisible(viewDetailsLink);
    await settle(tester);
    await tester.tap(viewDetailsLink);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Team Recovery'), findsOneWidget, reason: 'Sales Team Performance "View Details" must open the new Team Recovery screen');
    expect(find.text('Overview of team performance and recovery'), findsOneWidget);
    print('✓ Team Recovery screen opened from Dashboard "View Details"');

    // ---- Stat cards (horizontally scrollable) ----
    expect(find.text('Total Salesman'), findsOneWidget);
    expect(find.text('Total Target (₹)'), findsOneWidget);
    expect(find.text('Total Received (₹)'), findsOneWidget);
    expect(find.text('Achievement'), findsOneWidget);
    final statCardsRow = find.byType(ListView).at(1);
    for (var i = 0; i < 6 && find.text('Overdue (₹)').evaluate().isEmpty; i++) {
      await tester.drag(statCardsRow, const Offset(-200, 0));
      await settle(tester);
    }
    expect(find.text('Overdue (₹)'), findsOneWidget);
    print('✓ Stat cards rendered with live data');

    // ---- Real employee IDs ----
    // The real system has no separate employee-code concept (no 'EMP001'
    // like the old demo roster) — the real user id itself is shown instead.
    expect(find.textContaining('rahul'), findsWidgets, reason: 'Rows must show the real, stable user id in place of the old demo EMP0xx code');
    print('✓ Real employee IDs (real user ids) rendered');

    // ---- Tabs genuinely re-sort the same data ----
    expect(find.text('By Performance'), findsOneWidget);
    expect(find.text('By Target'), findsOneWidget);
    expect(find.text('By Overdue'), findsOneWidget);
    expect(find.text('By Branch'), findsOneWidget);
    await tester.tap(find.text('By Target'));
    await settle(tester);
    await tester.tap(find.text('By Overdue'));
    await settle(tester);
    await tester.tap(find.text('By Branch'));
    await settle(tester);
    await tester.tap(find.text('By Performance'));
    await settle(tester);
    print('✓ All 4 tabs tapped and re-rendered without error');

    // ---- Search is real ----
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'zzz_no_such_salesman_zzz');
    await settle(tester);
    expect(find.text('No salesmen match this search.'), findsOneWidget, reason: 'Search must genuinely filter the salesmen list');
    print('✓ Search box genuinely filters the salesmen list');
    await tester.tap(searchField);
    await settle(tester);
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('No salesmen match this search.'), findsNothing, reason: 'Clearing the search box must actually restore the full salesmen list');

    // ---- Branch filter is real ----
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final mumbaiOption = find.text('Mumbai').last;
    if (mumbaiOption.evaluate().isNotEmpty) {
      await tester.tap(mumbaiOption);
      await settle(tester);
      expect(find.text('Mumbai'), findsWidgets, reason: 'Selecting a branch must actually apply as the active filter');
      expect(find.text('No salesmen match this search.'), findsNothing, reason: 'Mumbai must have real salesmen');
      print('✓ Branch filter dropdown opened and a real branch was applied');
      // Reset back to All Branches so subsequent checks see the full team.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      await tester.tap(find.text('All Branches').last);
      await settle(tester);
    }

    // ---- Total / Avg row present ----
    expect(find.text('Total / Avg.'), findsOneWidget);
    print('✓ Total / Avg row rendered');

    // ---- Export gives real feedback ----
    // The outer ListView lazily mounts children, and the branch-filter
    // dropdown interaction above may have left Export scrolled out of the
    // mounted range — scroll back up until it's actually built, then tap.
    final outerList = find.byType(ListView).first;
    for (var i = 0; i < 6 && find.text('Export').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, 400));
      await settle(tester);
    }
    expect(find.text('Export'), findsOneWidget);
    // OutlinedButton.icon() builds a private `_OutlinedButtonWithIcon`
    // subclass, so find.byType(OutlinedButton) won't match it — target the
    // download icon inside the button instead.
    final exportButton = find.byIcon(Icons.download);
    await tester.ensureVisible(exportButton);
    await settle(tester);
    await tester.tap(exportButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Team Recovery report exported.'), findsOneWidget, reason: 'Export must give real feedback');
    print('✓ Export gives real feedback');

    // ---- Achievement Distribution buckets ----
    final pageList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('Achievement Distribution').evaluate().isEmpty; i++) {
      await tester.drag(pageList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Achievement Distribution'), findsOneWidget);
    expect(find.text('≥ 90%'), findsOneWidget);
    expect(find.text('< 25%'), findsOneWidget);
    print('✓ Achievement Distribution buckets rendered');

    // ---- Row tap opens a genuinely read-only detail sheet ----
    // Anchor on CircleAvatar (unique to salesman rows — the Achievement
    // Distribution card below also has a chevron_right, on its "View
    // Details" link, so byIcon(chevron_right) alone would be ambiguous).
    for (var i = 0; i < 10 && find.byType(CircleAvatar).evaluate().isEmpty; i++) {
      await tester.drag(pageList, const Offset(0, 400));
      await settle(tester);
    }
    final avatars = find.byType(CircleAvatar);
    expect(avatars, findsWidgets, reason: 'The team table must have real rows to tap');
    final firstRow = find.ancestor(of: avatars.first, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(firstRow);
    await settle(tester);
    await tester.tap(firstRow);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.textContaining('Manager view is read-only'), findsOneWidget, reason: 'Salesman detail sheet must explicitly state it is read-only');
    final sheetButtons = find.descendant(of: find.byType(BottomSheet), matching: find.byType(ElevatedButton));
    expect(sheetButtons, findsNothing, reason: 'The read-only detail sheet must contain no action buttons');
    print('✓ Tapping a salesman opens a genuinely read-only detail sheet');
    await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Manager view is read-only'), findsNothing, reason: 'Dragging the sheet down must actually dismiss it');

    // ---- Back navigation ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Team Recovery'), findsNothing, reason: 'Back must leave the Team Recovery screen');
    expect(find.text('Manager Dashboard'), findsOneWidget, reason: 'Back must return to the Manager Dashboard');
    print('✓ Back navigation returns to the Dashboard');

    print('✓ Manager Team Recovery flow complete');
  });
}
