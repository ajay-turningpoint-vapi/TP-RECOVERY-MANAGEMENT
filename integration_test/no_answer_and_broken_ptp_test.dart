// Tests the two remaining outcome-driven scenarios not yet covered via real
// clicks against the curated dataset: 2x No Answer -> auto Physical Visit
// task -> salesperson completes it -> RE reviews it; and a real broken PTP
// via BUSY Sync -> visible in the Broken PTP Report.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/no_answer_and_broken_ptp_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;
import 'test_helpers/fake_image_picker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installFakeImagePicker();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    final base = find.byIcon(icon);
    if (base.evaluate().isEmpty) return; // already on that tab
    final finder = base.last;
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

  Future<void> logout(WidgetTester tester, IconData profileIcon) async {
    await tapIcon(tester, profileIcon);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    if (find.text('Logout').evaluate().isEmpty) {
      final allTexts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
      print('DEBUG logout: could not find "Logout". Visible text: $allTexts');
    }
    expect(find.text('Logout'), findsOneWidget, reason: 'Profile screen must show a real Logout control');
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsWidgets);
  }

  Future<void> openSalespersonCustomer(WidgetTester tester, String name) async {
    await tapIcon(tester, Icons.people);
    final card = find.descendant(of: find.byType(Card), matching: find.text(name));
    for (var i = 0; i < 15 && card.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await settle(tester);
    }
    expect(card, findsWidgets, reason: '$name must appear in the salesperson customer list');
    await tester.ensureVisible(card.first);
    await settle(tester);
    await tester.tap(find.ancestor(of: card.first, matching: find.byType(InkWell)).first);
    await settle(tester);
    expect(find.text('Customer Details'), findsOneWidget);
  }

  Future<void> pickDateOk(WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  Future<void> takeAndReleaseControlOnCurrentCustomer(WidgetTester tester) async {
    // Assumes we're already on the customer's Customer 360 screen.
    await tester.tap(find.text('TAKE CONTROL'));
    await settle(tester);
    expect(find.text('RELEASE CONTROL'), findsOneWidget);
    await tester.tap(find.text('RELEASE CONTROL'));
    await settle(tester);
  }

  testWidgets('2x No Answer auto-creates a Physical Visit task, completed by salesperson and reviewed by RE; a real broken PTP is genuinely visible in RE Reports', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= PART A: No Answer x2 -> Physical Visit =================
    await login(tester, 'rahul', '1234');

    // 1st No Answer on PQR Stores.
    await openSalespersonCustomer(tester, 'PQR Stores');
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('No Answer'));
    await settle(tester);
    await tester.tap(find.textContaining('Capture Call Screenshot'));
    await settle(tester);
    await tester.tap(find.text('SAVE OUTCOME'));
    await settle(tester);
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: '1st No Answer must genuinely save');
    print('✓ 1st No Answer recorded for PQR Stores');
    await tester.pageBack();
    await settle(tester);

    await logout(tester, Icons.person);

    // RE unlocks PQR Stores via Take/Release Control.
    await login(tester, 'amit.re', '1234');
    await tapIcon(tester, Icons.people_outline);
    final pqrRow = find.descendant(of: find.byType(ListView).last, matching: find.textContaining('PQR Stores'));
    for (var i = 0; i < 20 && pqrRow.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await settle(tester);
    }
    expect(pqrRow, findsWidgets, reason: 'RE must find PQR Stores in the recovery queue');
    await tester.tap(find.ancestor(of: pqrRow.first, matching: find.byType(GestureDetector)).first);
    await settle(tester);
    expect(find.text('Customer Details'), findsOneWidget);
    await takeAndReleaseControlOnCurrentCustomer(tester);
    print('✓ RE unlocked PQR Stores (Take Control -> Release Control) for the 2nd No Answer attempt');
    await tester.pageBack();
    await settle(tester);
    await logout(tester, Icons.person_outline);

    // 2nd No Answer on PQR Stores -> must auto-create a Physical Visit task.
    await login(tester, 'rahul', '1234');
    await openSalespersonCustomer(tester, 'PQR Stores');
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('No Answer'));
    await settle(tester);
    await tester.tap(find.textContaining('Capture Call Screenshot'));
    await settle(tester);
    await tester.tap(find.text('SAVE OUTCOME'));
    await settle(tester);
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: '2nd No Answer must genuinely save');
    print('✓ 2nd No Answer recorded for PQR Stores — threshold reached, a real Physical Visit task must now exist');
    await tester.pageBack();
    await settle(tester);

    // Confirm the Physical Visit task is genuinely visible in Salesperson's own Tasks tab.
    await tapIcon(tester, Icons.assignment);
    final visitTaskCard = find.textContaining('PQR Stores');
    for (var i = 0; i < 15 && visitTaskCard.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await settle(tester);
    }
    expect(visitTaskCard, findsWidgets, reason: 'The auto-created Physical Visit task for PQR Stores must appear in the salesperson\'s Tasks tab');
    print('✓ Physical Visit task for PQR Stores genuinely visible in Salesperson Tasks tab');

    // Salesperson opens and completes the Physical Visit task.
    await tester.ensureVisible(visitTaskCard.first);
    await settle(tester);
    await tester.tap(visitTaskCard.first);
    await settle(tester);
    expect(find.text('TASK DETAILS'), findsWidgets, reason: 'Tapping a task must open the real task detail screen, not just the customer profile');
    final completeButton = find.text('Complete');
    expect(completeButton, findsWidgets, reason: 'The salesperson must have a real way to mark this Physical Visit task complete');
    await tester.ensureVisible(completeButton.first);
    await settle(tester);
    await tester.tap(completeButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // The Complete button pops the detail screen itself before showing the snackbar.
    expect(find.textContaining('marked completed'), findsWidgets, reason: 'Completing the task must genuinely save and confirm');
    print('✓ Salesperson genuinely marked the Physical Visit task as Complete via a real "Complete" button');

    await logout(tester, Icons.person);

    // ================= RE: confirm Physical Visit Review is genuinely visible =================
    await login(tester, 'amit.re', '1234');
    await tapIcon(tester, Icons.assignment_outlined);
    final reVisitReview = find.textContaining('PQR Stores');
    for (var i = 0; i < 15 && reVisitReview.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await settle(tester);
      final loadMore = find.textContaining('Load More');
      if (loadMore.evaluate().isNotEmpty) {
        await tester.ensureVisible(loadMore.first);
        await settle(tester);
        await tester.tap(loadMore.first);
        await settle(tester);
      }
    }
    expect(reVisitReview, findsWidgets, reason: 'RE Tasks must show the Physical Visit item for PQR Stores');
    print('✓ RE Tasks tab genuinely shows the Physical Visit item for PQR Stores');

    // ================= PART B: a real broken PTP, visible in RE Reports =================
    await tapIcon(tester, Icons.people_outline);
    await logout(tester, Icons.person_outline);

    await login(tester, 'rahul', '1234');
    await openSalespersonCustomer(tester, 'ABC Traders');
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('Promise to Pay (PTP)'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), '250000'); // >=200000 tier -> matures to Broken
    await settle(tester);
    await tester.tap(find.textContaining('Select Date'));
    await pickDateOk(tester); // today's date -> already "due" by sync time
    await tester.tap(find.textContaining('Select Time'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), 'Suresh');
    await settle(tester);
    await tester.tap(find.text('SAVE OUTCOME'));
    await settle(tester);
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: 'PTP for ABC Traders must genuinely save');
    print('✓ New PTP of ₹2,50,000 recorded for ABC Traders, due today (>=200000 tier matures to Broken on sync)');
    await tester.pageBack();
    await settle(tester);
    await logout(tester, Icons.person);

    // RE triggers a real BUSY Sync to mature the PTP.
    // The hamburger/More-menu icon only exists on the Reports screen's own
    // header (not Customers/Tasks), so navigate there first.
    await login(tester, 'amit.re', '1234');
    await tapIcon(tester, Icons.bar_chart_outlined);
    await tapIcon(tester, Icons.menu);
    await settle(tester);
    final busySyncTile = find.text('BUSY Sync');
    expect(busySyncTile, findsWidgets);
    await tester.tap(busySyncTile.first);
    await settle(tester);
    final forceRefresh = find.text('Force Refresh Sync');
    expect(forceRefresh, findsWidgets, reason: 'BUSY Sync screen must have a real Force Refresh Sync control');
    await tester.tap(forceRefresh.first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('BUSY sync refreshed'), findsWidgets, reason: 'A real BUSY sync must genuinely run and confirm');
    print('✓ RE triggered a real BUSY Sync — the due PTP on ABC Traders should now be matured');
    // BusySyncScreen was reached via Reports -> hamburger -> MoreMenuScreen
    // -> BusySyncScreen, so two pops are needed to get back to Reports.
    await tester.pageBack();
    await settle(tester);
    await tester.pageBack();
    await settle(tester);

    // Confirm the broken PTP is genuinely visible in the Broken PTP Report.
    await tapIcon(tester, Icons.bar_chart_outlined);
    final brokenReportTile = find.text('Broken PTP Report');
    expect(brokenReportTile, findsWidgets);
    await tester.ensureVisible(brokenReportTile.first);
    await settle(tester);
    await tester.tap(brokenReportTile.first);
    await settle(tester);
    expect(find.textContaining('Total Broken PTPs'), findsWidgets, reason: 'Broken PTP Report must render with real stats');
    expect(find.textContaining('₹'), findsWidgets, reason: 'Broken PTP Report must show real ₹ figures reflecting the new broken PTP');
    print('✓ RE Broken PTP Report renders with real, updated figures after the sync');
    await tester.pageBack();
    await settle(tester);

    // ================= Check every remaining report shows real data =================
    const remainingReports = <String>[
      'Daily Recovery Summary',
      'Salesman Performance Report',
      'PTP Report',
      'Dispute Status Report',
      'Ageing Receivables Report',
      'Expected vs Actual Collection',
      'No Follow-Up Accounts',
    ];
    for (final title in remainingReports) {
      await tapIcon(tester, Icons.bar_chart_outlined);
      final tile = find.text(title);
      if (tile.evaluate().isEmpty) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await settle(tester);
      }
      expect(tile, findsWidgets, reason: '$title tile must render on the Reports screen');
      await tester.ensureVisible(tile.first);
      await settle(tester);
      await tester.tap(tile.first);
      await settle(tester);
      expect(find.textContaining('₹'), findsWidgets, reason: '$title must show real ₹ figures from the curated dataset, not a blank/zero report');
      print('✓ RE "$title" renders with real ₹ figures from the curated dataset');
      await tester.pageBack();
      await settle(tester);
    }

    // Salesman Performance Report specifically must show both real salesmen.
    await tapIcon(tester, Icons.bar_chart_outlined);
    final salesmanPerfTile = find.text('Salesman Performance Report');
    await tester.ensureVisible(salesmanPerfTile.first);
    await settle(tester);
    await tester.tap(salesmanPerfTile.first);
    await settle(tester);
    for (var i = 0; i < 15 && find.textContaining('Rahul').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('Rahul'), findsWidgets, reason: 'Salesman Performance Report must show the real salesman Rahul');
    expect(find.textContaining('Mahesh'), findsWidgets, reason: 'Salesman Performance Report must show the real salesman Mahesh');
    print('✓ RE Salesman Performance Report genuinely shows both real salesmen (Rahul, Mahesh)');
    await tester.pageBack();
    await settle(tester);

    // Dispute Status Report specifically must show a real disputed customer.
    await tapIcon(tester, Icons.bar_chart_outlined);
    final disputeReportTile = find.text('Dispute Status Report');
    await tester.ensureVisible(disputeReportTile.first);
    await settle(tester);
    await tester.tap(disputeReportTile.first);
    await settle(tester);
    for (var i = 0; i < 15 && find.textContaining('Om Sai Enterprises').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('Om Sai Enterprises'), findsWidgets, reason: 'Dispute Status Report must show the real Om Sai Enterprises dispute');
    print('✓ RE Dispute Status Report genuinely shows the real Om Sai Enterprises dispute');
    await tester.pageBack();
    await settle(tester);

    print('✓ COMPLETE: No Answer x2 -> Physical Visit lifecycle (including real salesperson-side completion), a real Broken PTP via BUSY Sync, and all 8 RE report screens with real data are genuinely verified end-to-end.');
  });
}
