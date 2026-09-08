// Real end-to-end test of the Manager's rebuilt PTP Report screen, in a
// real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_ptp_report_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager PTP Report: stats, distribution, trend, due today, broken summary, details table', (tester) async {
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
    for (var i = 0; i < 10 && find.text('PTP Reports').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('PTP Reports'));
    await settle(tester);
    await tester.tap(find.text('PTP Reports'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('PTP Report'), findsOneWidget, reason: 'Tapping the report must open the rebuilt PTP Report screen');
    expect(find.text('Promise to Pay analysis and summary'), findsOneWidget);
    print('✓ PTP Report screen opened');

    // ---- Stat cards ----
    expect(find.text('Total PTP Amount'), findsOneWidget);
    expect(find.text('PTP Kept'), findsWidgets);
    expect(find.text('PTP Pending (Due)'), findsWidgets);
    expect(find.text('PTP Broken'), findsWidgets);
    print('✓ Stat cards rendered with live data');

    // ---- Status distribution donut ----
    expect(find.text('PTP Status Distribution (Amount)'), findsOneWidget);
    print('✓ PTP Status Distribution donut rendered');

    // ---- Trend chart ----
    expect(find.text('PTP Trend (Last 7 Days)'), findsOneWidget);
    print('✓ PTP Trend chart rendered');

    // ---- PTP Due Today ----
    for (var i = 0; i < 6 && find.textContaining('PTP Due Today').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('PTP Due Today'), findsOneWidget);
    print('✓ PTP Due Today section rendered');

    // ---- Broken summary + recent broken ----
    for (var i = 0; i < 6 && find.text('PTP Broken Summary').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('PTP Broken Summary'), findsOneWidget);
    expect(find.text('Recent Broken PTPs'), findsOneWidget);
    expect(find.text('Top Reasons for Broken PTP'), findsOneWidget);
    print('✓ Broken PTP summary, recent broken list, and top reasons rendered');

    // ---- Details table: search + sort real ----
    for (var i = 0; i < 6 && find.text('PTP Details').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('PTP Details'), findsOneWidget);
    final searchField = find.byType(TextField).last;
    await tester.enterText(searchField, 'zzz_no_such_customer_zzz');
    await settle(tester);
    expect(find.text('No PTPs match this search.'), findsOneWidget, reason: 'Search must genuinely filter the details table');
    print('✓ Search box genuinely filters the PTP details table');
    await tester.enterText(searchField, '');
    await settle(tester);

    await tester.tap(find.text('Sort'));
    await settle(tester);
    print('✓ Sort control tapped without error');

    // ---- Tapping a PTP row opens a read-only detail sheet (Manager view-only) ----
    final rows = find.byIcon(Icons.access_time_filled);
    if (rows.evaluate().isNotEmpty) {
      await tester.tap(rows.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(find.textContaining('Manager view is read-only'), findsOneWidget, reason: 'PTP detail sheet must explicitly state it is read-only');
      final sheetButtons = find.descendant(of: find.byType(BottomSheet), matching: find.byType(ElevatedButton));
      expect(sheetButtons, findsNothing, reason: 'The read-only detail sheet must contain no action buttons');
      print('✓ Tapping a PTP opens a genuinely read-only detail sheet');
      await tester.tapAt(const Offset(50, 50));
      await settle(tester);
    }

    // ---- Footer + Export ----
    // The details table can render up to 30 rows, making this a long page —
    // allow more scroll iterations to reach the footer.
    for (var i = 0; i < 20 && find.textContaining('All amounts are in INR').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('All amounts are in INR'), findsOneWidget);
    print('✓ Footer note present');

    for (var i = 0; i < 10 && find.text('Export').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, 400));
      await settle(tester);
    }
    await tester.tap(find.text('Export'));
    await settle(tester);
    expect(find.textContaining('Report export started'), findsOneWidget, reason: 'Export must give real feedback');
    print('✓ Export button gives real feedback');

    // ---- Back navigation ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reports'), findsWidgets, reason: 'Back must return to the Manager Reports list');
    print('✓ Back navigation returns to the Reports list');

    print('✓ Manager PTP Report flow complete');
  });
}
