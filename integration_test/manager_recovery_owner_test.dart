// Real end-to-end test of the Manager's new Recovery Owner — View All
// screen, in a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_recovery_owner_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Recovery Owner: real stats, search, branch filter, table, read-only detail', (tester) async {
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

    // Reached via the Manager Reports list — the Dashboard's "Sales Team
    // Performance (Today)" View Details link now correctly opens Team
    // Recovery instead (a separate, real screen), so Recovery Owner has its
    // own dedicated entry point in Reports.
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.bar_chart_outlined)));
    await settle(tester);
    final reportsList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('Recovery Owner').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    final reportTile = find.text('Recovery Owner');
    await tester.ensureVisible(reportTile);
    await settle(tester);
    await tester.tap(reportTile);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Recovery Owner – View All'), findsOneWidget, reason: 'Reports "Recovery Owner" tile must open the Recovery Owner screen');
    expect(find.text('All recovery owners with summary of performance'), findsOneWidget);
    print('✓ Recovery Owner screen opened from Reports');

    // ---- Stat cards (horizontally scrollable — check before scrolling right) ----
    expect(find.text('Total Owners'), findsOneWidget);
    expect(find.text('Total Target (₹)'), findsOneWidget);
    expect(find.text('Total Received (₹)'), findsOneWidget);
    expect(find.text('Achievement'), findsOneWidget);
    // .at(1): index 0 is the screen's own outer (vertical) ListView; the
    // horizontal stat-cards ListView is nested inside it.
    final statCardsRow = find.byType(ListView).at(1);
    for (var i = 0; i < 6 && find.text('Overdue (₹)').evaluate().isEmpty; i++) {
      await tester.drag(statCardsRow, const Offset(-200, 0));
      await settle(tester);
    }
    expect(find.text('Overdue (₹)'), findsOneWidget);
    print('✓ Stat cards rendered with live data');

    // ---- Real employee IDs, not fabricated per-render ----
    // The real system has no separate employee-code concept (no 'EMP001'
    // like the old demo roster) — the real user id itself is shown instead.
    expect(find.textContaining('rahul'), findsWidgets, reason: 'Owners must show the real, stable user id in place of the old demo EMP0xx code');
    expect(find.text('Salesman'), findsWidgets);
    print('✓ Real employee IDs and Salesman tags rendered');

    // ---- Search is real ----
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'zzz_no_such_owner_zzz');
    await settle(tester);
    expect(find.text('No recovery owners match this search.'), findsOneWidget, reason: 'Search must genuinely filter the owner list');
    print('✓ Search box genuinely filters the owner list');
    await tester.tap(searchField);
    await settle(tester);
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('No recovery owners match this search.'), findsNothing, reason: 'Clearing the search box must actually restore the full owner list');

    // ---- Branch filter is real ----
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final mumbaiOption = find.text('Mumbai').last;
    if (mumbaiOption.evaluate().isNotEmpty) {
      await tester.tap(mumbaiOption);
      await settle(tester);
      expect(find.text('Mumbai'), findsWidgets, reason: 'Selecting a branch must actually apply as the active filter');
      expect(find.text('No recovery owners match this search.'), findsNothing, reason: 'Mumbai must have real owners — if this fails, the search query was not actually cleared before filtering');
      print('✓ Branch filter dropdown opened and a real branch was applied');
    }

    // ---- Total row present ----
    expect(find.text('Total'), findsOneWidget);
    print('✓ Total row rendered');

    // ---- Row tap opens a genuinely read-only detail sheet ----
    // The owner table sits inside the screen's outer ListView, which lazily
    // builds its children — scroll until at least one row is actually built.
    final pageList = find.byType(ListView).first;
    for (var i = 0; i < 8 && find.byIcon(Icons.chevron_right).evaluate().isEmpty; i++) {
      await tester.drag(pageList, const Offset(0, -400));
      await settle(tester);
    }
    final ownerRows = find.byIcon(Icons.chevron_right);
    expect(ownerRows, findsWidgets, reason: 'The owner table must have real rows to tap');
    await tester.tap(ownerRows.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.textContaining('Manager view is read-only'), findsOneWidget, reason: 'Owner detail sheet must explicitly state it is read-only');
    final sheetButtons = find.descendant(of: find.byType(BottomSheet), matching: find.byType(ElevatedButton));
    expect(sheetButtons, findsNothing, reason: 'The read-only detail sheet must contain no action buttons');
    print('✓ Tapping an owner opens a genuinely read-only detail sheet');
    // Dismiss the modal sheet by dragging it down (the standard, reliable way
    // to close a BottomSheet in widget tests) rather than guessing barrier
    // coordinates, so the real Back button tap below actually reaches the
    // Back IconButton instead of racing the sheet's dismiss animation.
    await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Manager view is read-only'), findsNothing, reason: 'Dragging the sheet down must actually dismiss it before Back is tested');
    print('✓ Dragging down dismissed the detail sheet');

    // ---- Back navigation ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Recovery Owner – View All'), findsNothing, reason: 'Back must leave the Recovery Owner screen');
    expect(find.text('Reports'), findsOneWidget, reason: 'Back must return to the Reports tab it was opened from');
    print('✓ Back navigation returns to Reports');

    print('✓ Manager Recovery Owner flow complete');
  });
}
