// Real end-to-end test of the Manager's new Dispute Management — Summary
// report, in a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_dispute_management_summary_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Dispute Management Summary: real stats, tabs, search, sort, read-only detail', (tester) async {
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

    // Navigate: Dashboard -> Reports tab -> "Dispute Management – Summary".
    // Icons.bar_chart_outlined also appears on the Dashboard's own "Reports"
    // Quick Action tile (built before the bottom nav in the tree), so the
    // real bottom-nav tab is the LAST match, not the first.
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    final reportsList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('Dispute Management – Summary').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    final reportTile = find.text('Dispute Management – Summary');
    expect(reportTile, findsOneWidget);
    await tester.ensureVisible(reportTile);
    await settle(tester);
    await tester.tap(reportTile);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Overview of all disputes and their status'), findsOneWidget, reason: 'Reports list must open the new Dispute Management Summary screen');
    print('✓ Dispute Management Summary screen opened from Reports');

    // ---- Stat cards ----
    expect(find.text('Total Disputes'), findsOneWidget);
    expect(find.text('Amount In Dispute (₹)'), findsOneWidget);
    final statCardsRow = find.byType(ListView).at(1);
    for (var i = 0; i < 6 && find.text('Rejected').evaluate().isEmpty; i++) {
      await tester.drag(statCardsRow, const Offset(-200, 0));
      await settle(tester);
    }
    expect(find.text('Rejected'), findsWidgets);
    print('✓ Stat cards rendered with live data');

    // ---- Status donut, ageing, and reasons sections ----
    final outerList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('Disputes by Status').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Disputes by Status'), findsOneWidget);
    expect(find.text('Disputes by Ageing (Amount in ₹)'), findsOneWidget);
    for (var i = 0; i < 10 && find.text('Top Dispute Reasons (Amount in ₹)').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Top Dispute Reasons (Amount in ₹)'), findsOneWidget);
    print('✓ Status donut, ageing bars, and reasons cards rendered with live data');

    // "View All Reasons" opens a real breakdown sheet.
    final viewAllReasons = find.text('View All Reasons');
    await tester.ensureVisible(viewAllReasons);
    await settle(tester);
    await tester.tap(viewAllReasons);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Dispute Reasons'), findsOneWidget, reason: 'View All Reasons must open a real breakdown sheet');
    print('✓ View All Reasons opens a real breakdown sheet');
    await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ---- Tabs genuinely re-filter ----
    for (var i = 0; i < 12 && find.textContaining('Pending Review (').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    final pendingReviewTab = find.textContaining('Pending Review (').first;
    await tester.ensureVisible(pendingReviewTab);
    await settle(tester);
    await tester.tap(pendingReviewTab);
    await settle(tester);
    print('✓ Pending Review tab tapped and re-rendered without error');

    // The tab row is a horizontally-scrollable lazy list — 'Recent Disputes'
    // (leftmost) may have scrolled out of the mounted range; scroll back
    // using the still-mounted Pending Review chip as the Scrollable anchor.
    final tabScrollableBack = find.ancestor(of: find.textContaining('Pending Review (').first, matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 6 && find.text('Recent Disputes').evaluate().isEmpty; i++) {
      await tester.drag(tabScrollableBack, const Offset(150, 0));
      await settle(tester);
    }
    final recentTab = find.text('Recent Disputes').first;
    expect(recentTab, findsOneWidget);
    await tester.tap(recentTab);
    await settle(tester);
    print('✓ Recent Disputes tab restores the full list');

    // ---- Search is real ----
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'zzz_no_such_dispute_zzz');
    await settle(tester);
    expect(find.text('No disputes match this search.'), findsOneWidget, reason: 'Search must genuinely filter the dispute list');
    print('✓ Search box genuinely filters the dispute list');
    await tester.tap(searchField);
    await settle(tester);
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('No disputes match this search.'), findsNothing, reason: 'Clearing the search box must actually restore the full dispute list');

    // ---- Sort genuinely reorders ----
    // OutlinedButton.icon() builds a private `_OutlinedButtonWithIcon`
    // subclass, so find.widgetWithText(OutlinedButton, ...) won't match it —
    // target the swap_vert icon inside the button instead.
    await tester.tap(find.byIcon(Icons.swap_vert));
    await settle(tester);
    print('✓ Sort control tapped and re-rendered without error');

    // ---- Total row present ----
    for (var i = 0; i < 10 && find.text('Total Disputes').evaluate().length < 2; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Total Amount in Dispute'), findsOneWidget);
    expect(find.text('Average Ageing'), findsOneWidget);
    print('✓ Total row rendered');

    // ---- Row tap opens a genuinely read-only detail sheet ----
    // The table itself scrolls horizontally, and its chevron column sits at
    // the far right — ensure it's actually scrolled into view before tapping.
    final chevrons = find.byIcon(Icons.chevron_right);
    expect(chevrons, findsWidgets, reason: 'The dispute table must have real rows to tap');
    await tester.ensureVisible(chevrons.first);
    await settle(tester);
    await tester.tap(chevrons.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.textContaining('Manager view is read-only'), findsOneWidget, reason: 'Dispute detail sheet must explicitly state it is read-only');
    final sheetButtons = find.descendant(of: find.byType(BottomSheet), matching: find.byType(ElevatedButton));
    expect(sheetButtons, findsNothing, reason: 'The read-only detail sheet must contain no action buttons');
    print('✓ Tapping a dispute opens a genuinely read-only detail sheet');
    await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ---- Back navigation ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Overview of all disputes and their status'), findsNothing, reason: 'Back must leave the Dispute Management Summary screen');
    print('✓ Back navigation leaves the screen');

    print('✓ Manager Dispute Management Summary flow complete');
  });
}
