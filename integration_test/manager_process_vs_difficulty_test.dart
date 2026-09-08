// Real end-to-end test of the new Process Discipline vs Customer Difficulty
// separation added to the Manager's Salesman Performance and Team Recovery
// screens, in a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_process_vs_difficulty_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Process vs Customer Difficulty: real, independent metrics on both performance screens', (tester) async {
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

    // ---- Manager Salesman Performance screen ----
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    final reportsList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('Salesman Performance').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    final reportTile = find.text('Salesman Performance');
    expect(reportTile, findsOneWidget);
    await tester.ensureVisible(reportTile);
    await settle(tester);
    await tester.tap(reportTile);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Salesmen Performance'), findsOneWidget, reason: 'Reports list must open the Salesman Performance screen');
    print('✓ Salesman Performance screen opened');

    final outerList = find.byType(ListView).first;
    for (var i = 0; i < 12 && find.text('Process Discipline vs Customer Difficulty').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Process Discipline vs Customer Difficulty'), findsOneWidget, reason: 'The new process-vs-difficulty card must be present');
    expect(find.textContaining('Process: '), findsWidgets, reason: 'Real per-salesman process compliance badges must render');
    expect(find.textContaining('Customer: '), findsWidgets, reason: 'Real per-salesman customer difficulty badges must render');
    print('✓ Process Discipline vs Customer Difficulty card rendered with real badges');

    // Tap a row in the new card to open its detail sheet — anchor on the
    // "Process: <verdict>" badge text (unique to this card's rows) and walk
    // up to its InkWell, rather than scoping by ancestor Column (too broad —
    // matches page-level Columns containing unrelated InkWells too).
    final processBadge = find.textContaining('Process: ').first;
    final firstProcessRow = find.ancestor(of: processBadge, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(firstProcessRow);
    await settle(tester);
    await tester.tap(firstProcessRow);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Process Compliance'), findsOneWidget, reason: 'Detail sheet must show the Process Compliance card');
    // "Customer Difficulty" appears twice by design: the badge card label
    // and the section header above its key-value rows.
    expect(find.text('Customer Difficulty'), findsNWidgets(2), reason: 'Detail sheet must show the Customer Difficulty badge and section header');
    expect(find.text('Task Completion Rate'), findsOneWidget);
    expect(find.text('Valid Next Action Rate'), findsOneWidget);
    expect(find.text('Broken PTPs'), findsOneWidget);
    expect(find.text('Escalated Accounts (L1-L4)'), findsOneWidget);
    print('✓ Detail sheet shows independent process-discipline and customer-difficulty metrics');
    await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Row tap in the main details table must also open the same detail sheet
    // (previously a dead chevron with no onTap).
    for (var i = 0; i < 12 && find.text('Salesmen Performance Details').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Salesmen Performance Details'), findsOneWidget);
    // Anchor on the search hint text (unique to this table) and walk down
    // to a real row's InkWell via its chevron_right icon, rather than
    // scoping by ancestor Column (too broad on this page).
    final chevrons = find.byIcon(Icons.chevron_right);
    expect(chevrons, findsWidgets, reason: 'The details table rows must have a real chevron per row');
    final lastChevronRow = find.ancestor(of: chevrons.last, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(lastChevronRow);
    await settle(tester);
    await tester.tap(lastChevronRow);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Process Compliance'), findsOneWidget, reason: 'Tapping a details-table row must open the same real detail sheet');
    print('✓ Details table row tap (previously dead) now opens the real detail sheet');
    await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Back returns to the Reports tab (still selected in the bottom nav's
    // IndexedStack) — switch to Dashboard explicitly before scrolling it.
    await tester.tap(find.byIcon(Icons.dashboard_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // ---- Manager Team Recovery screen ----
    for (var i = 0; i < 10 && find.text('Sales Team Performance (Today)').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -400));
      await settle(tester);
    }
    // Manager Dashboard's "Sales Team Performance (Today)" card links here.
    final performanceHeaderRow = find.ancestor(of: find.text('Sales Team Performance (Today)'), matching: find.byType(Row)).first;
    final viewDetailsLink = find.descendant(of: performanceHeaderRow, matching: find.text('View Details'));
    await tester.ensureVisible(viewDetailsLink);
    await settle(tester);
    await tester.tap(viewDetailsLink);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Team Recovery'), findsOneWidget);
    print('✓ Team Recovery screen opened');

    final teamOuterList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.byType(CircleAvatar).evaluate().isEmpty; i++) {
      await tester.drag(teamOuterList, const Offset(0, 400));
      await settle(tester);
    }
    final avatars = find.byType(CircleAvatar);
    expect(avatars, findsWidgets, reason: 'The team table must have real rows to tap');
    final firstRow = find.ancestor(of: avatars.first, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(firstRow);
    await settle(tester);
    await tester.tap(firstRow);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Process Compliance'), findsOneWidget, reason: 'Team Recovery detail sheet must now include Process Compliance');
    expect(find.text('Customer Difficulty'), findsOneWidget, reason: 'Team Recovery detail sheet must now include Customer Difficulty');
    expect(find.text('Task Completion Rate'), findsOneWidget);
    expect(find.text('Escalated Accounts (L1-L4)'), findsOneWidget);
    final sheetButtons = find.descendant(of: find.byType(BottomSheet), matching: find.byType(ElevatedButton));
    expect(sheetButtons, findsNothing, reason: 'The enriched detail sheet must still contain no action buttons');
    print('✓ Team Recovery detail sheet shows the same real process-vs-difficulty split, still read-only');

    print('✓ Manager Process vs Customer Difficulty flow complete');
  });
}
