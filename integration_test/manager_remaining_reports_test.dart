// Real end-to-end test of the Manager's remaining rebuilt report screens
// (Broken PTP, Dispute Status, Ageing Receivables, No Follow-up), in a real
// Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_remaining_reports_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  Future<void> openReport(WidgetTester tester, dynamic reportsList, String reportTitle) async {
    for (var i = 0; i < 8 && find.text(reportTitle).evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    await tester.ensureVisible(find.text(reportTitle));
    await settle(tester);
    await tester.tap(find.text(reportTitle));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
  }

  Future<void> scrollDownUntil(WidgetTester tester, String text) async {
    final list = find.byType(ListView).first;
    for (var i = 0; i < 8 && find.text(text).evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -400));
      await settle(tester);
    }
  }

  Future<void> goBackToReportsList(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reports'), findsWidgets, reason: 'Back must return to the Manager Reports list');
  }

  testWidgets('Manager remaining reports: Broken PTP, Dispute Status, Ageing Receivables, No Follow-up', (tester) async {
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

    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await settle(tester);
    final reportsList = find.byType(ListView).first;

    // ---- Broken PTP Report ----
    await openReport(tester, reportsList, 'Broken PTP Reports');
    expect(find.text('Broken PTP Report'), findsOneWidget);
    expect(find.text('Total Broken PTPs'), findsOneWidget);
    expect(find.text('Broken PTP Status Distribution'), findsOneWidget);
    await scrollDownUntil(tester, 'Broken PTP Details');
    expect(find.text('Broken PTP Details'), findsOneWidget);
    print('✓ Broken PTP Report opened with real stat cards, distribution and details');
    await goBackToReportsList(tester);

    // ---- Dispute Status Report ----
    await openReport(tester, reportsList, 'Dispute Status Report');
    expect(find.text('Dispute Status Report'), findsOneWidget);
    expect(find.text('Total Disputes'), findsOneWidget);
    expect(find.text('Disputes by Status'), findsOneWidget);
    expect(find.text('Disputes by Reason'), findsOneWidget);
    await scrollDownUntil(tester, 'Disputes Aging');
    expect(find.text('Disputes Aging'), findsOneWidget);
    print('✓ Dispute Status Report opened with real stat cards, distribution, reasons, aging');
    await goBackToReportsList(tester);

    // ---- Ageing Receivables Report ----
    await openReport(tester, reportsList, 'Ageing Receivables');
    expect(find.text('Ageing Receivables'), findsWidgets);
    expect(find.text('Total Outstanding'), findsOneWidget);
    expect(find.text('Ageing Summary'), findsOneWidget);
    await scrollDownUntil(tester, 'Ageing Receivables Details');
    expect(find.text('Ageing Receivables Details'), findsOneWidget);
    print('✓ Ageing Receivables Report opened with real stat cards and details');
    await goBackToReportsList(tester);

    // ---- No Follow-up Report ----
    await openReport(tester, reportsList, 'No Follow-up Report');
    expect(find.text('No Follow-up Report'), findsWidgets);
    expect(find.text('No Follow-Up Accounts'), findsOneWidget);
    await scrollDownUntil(tester, 'Priority Summary');
    expect(find.text('Priority Summary'), findsOneWidget);
    await scrollDownUntil(tester, 'No Follow-Up Account List');
    expect(find.text('No Follow-Up Account List'), findsOneWidget);
    print('✓ No Follow-up Report opened with real stat cards, priority summary and details');

    // ---- Real search + tap-through on this last report ----
    final searchField = find.byType(TextField).last;
    await tester.enterText(searchField, 'zzz_no_such_account_zzz');
    await settle(tester);
    expect(find.text('No accounts match this search.'), findsOneWidget, reason: 'Search must genuinely filter the account list');
    print('✓ Search box genuinely filters the No Follow-up account list');
    await tester.enterText(searchField, '');
    await settle(tester);

    // ---- Export gives real feedback ----
    // The Export button lives in the fixed header, outside the scrollable
    // list, so it's already on screen regardless of scroll position.
    await tester.tap(find.text('Export'));
    await settle(tester);
    expect(find.textContaining('Report export started'), findsOneWidget, reason: 'Export must give real feedback');
    print('✓ Export button gives real feedback');

    await goBackToReportsList(tester);

    print('✓ Manager remaining reports flow complete');
  });
}
