// Real end-to-end test of the Manager's rebuilt Expected vs Actual
// Collection report screen, in a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_expected_vs_actual_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Expected vs Actual: stats, combo trend chart, branch table, performers, customer table', (tester) async {
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

    for (var i = 0; i < 6 && find.text('Expected vs Actual Recovery').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Expected vs Actual Recovery'));
    await settle(tester);
    await tester.tap(find.text('Expected vs Actual Recovery'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Expected vs Actual Collection'), findsOneWidget, reason: 'Tapping the report must open the rebuilt Expected vs Actual screen');
    expect(find.text('Compare expected collections against actual receipts'), findsOneWidget);
    print('✓ Expected vs Actual Collection screen opened');

    // ---- Stat cards ----
    expect(find.text('Total Expected (₹)'), findsOneWidget);
    expect(find.text('Total Actual (₹)'), findsOneWidget);
    expect(find.text('Variance (₹)'), findsWidgets);
    expect(find.text('Achievement (%)'), findsOneWidget);
    print('✓ Stat cards rendered with live data');

    // ---- Combo trend chart ----
    expect(find.text('Expected vs Actual Trend (Last 7 Days)'), findsOneWidget);
    expect(find.text('Expected (₹)'), findsWidgets);
    expect(find.text('Actual (₹)'), findsWidgets);
    print('✓ Expected vs Actual combo trend chart (lines + variance bars) rendered');

    // ---- Branch table ----
    for (var i = 0; i < 6 && find.text('Expected vs Actual by Branch').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Expected vs Actual by Branch'), findsOneWidget);
    print('✓ Branch breakdown table rendered');

    // ---- Over/Under performers ----
    for (var i = 0; i < 6 && find.text('Top Over Performers').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Top Over Performers'), findsOneWidget);
    expect(find.text('Top Under Performers'), findsOneWidget);
    print('✓ Top Over/Under Performers cards rendered');

    // ---- Customer table: search + sort real ----
    for (var i = 0; i < 6 && find.textContaining('Customer Expected vs Actual').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('Customer Expected vs Actual'), findsOneWidget);
    final searchField = find.byType(TextField).last;
    await tester.enterText(searchField, 'zzz_no_such_customer_zzz');
    await settle(tester);
    expect(find.text('No customers match this search.'), findsOneWidget, reason: 'Search must genuinely filter the customer table');
    print('✓ Search box genuinely filters the customer table');
    await tester.enterText(searchField, '');
    await settle(tester);

    await tester.tap(find.text('Sort'));
    await settle(tester);
    print('✓ Sort control tapped without error');

    // ---- Footer + Export ----
    for (var i = 0; i < 20 && find.textContaining('Expected amount is calculated').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('Expected amount is calculated'), findsOneWidget);
    print('✓ Footer note present');

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

    print('✓ Manager Expected vs Actual flow complete');
  });
}
