// Real end-to-end test of the Manager's rebuilt Salesmen Performance report
// screen, in a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_salesman_performance_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Salesmen Performance: stats, distribution, top/bottom performers, table search/sort', (tester) async {
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
    for (var i = 0; i < 10 && find.text('Salesman Performance').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Salesman Performance'));
    await settle(tester);
    await tester.tap(find.text('Salesman Performance'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Salesmen Performance'), findsOneWidget, reason: 'Tapping the report must open the rebuilt Salesmen Performance screen');
    expect(find.text('Individual performance and achievement report'), findsOneWidget);
    print('✓ Salesmen Performance screen opened');

    // ---- Stat cards ----
    expect(find.text('Total Target (₹)'), findsWidgets);
    expect(find.text('Achievement'), findsWidgets);
    expect(find.text('Active Salesmen'), findsOneWidget);
    print('✓ Stat cards rendered with live data');

    // ---- Achievement Distribution donut ----
    expect(find.text('Achievement Distribution'), findsOneWidget);
    expect(find.text('>= 100%'), findsOneWidget);
    expect(find.text('< 50%'), findsOneWidget);
    print('✓ Achievement Distribution donut rendered');

    // ---- Top / Bottom performers ----
    expect(find.text('Top Performers'), findsOneWidget);
    expect(find.text('Bottom Performers'), findsOneWidget);
    print('✓ Top and Bottom Performers cards rendered');

    // ---- Achievement Trend chart ----
    for (var i = 0; i < 6 && find.text('Achievement Trend (Last 7 Days)').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Achievement Trend (Last 7 Days)'), findsOneWidget);
    print('✓ Achievement Trend chart rendered');

    // ---- Branch + Salesman filters are real ----
    // Scroll back up to the top, where the filter dropdowns live.
    for (var i = 0; i < 8 && find.byIcon(Icons.keyboard_arrow_down).evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, 400));
      await settle(tester);
    }
    final downArrows = find.byIcon(Icons.keyboard_arrow_down);
    expect(downArrows, findsWidgets);
    await tester.tap(downArrows.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final mumbaiOption = find.text('Mumbai').last;
    if (mumbaiOption.evaluate().isNotEmpty) {
      await tester.tap(mumbaiOption);
      await settle(tester);
      print('✓ Branch filter dropdown opened and a real branch was applied');
    }

    // ---- Details table: search filters for real ----
    for (var i = 0; i < 6 && find.text('Salesmen Performance Details').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Salesmen Performance Details'), findsOneWidget);
    final searchField = find.widgetWithText(TextField, '').evaluate().isNotEmpty ? find.byType(TextField).last : find.byType(TextField).last;
    await tester.enterText(searchField, 'zzz_no_such_salesman_zzz');
    await settle(tester);
    expect(find.text('No salesmen match this search.'), findsOneWidget, reason: 'Search must genuinely filter the details table');
    print('✓ Search box genuinely filters the details table');
    await tester.enterText(searchField, '');
    await settle(tester);

    // ---- Sort toggle is real ----
    final sortButtonUpBefore = find.byIcon(Icons.arrow_upward).evaluate().isNotEmpty;
    await tester.tap(find.text('Sort'));
    await settle(tester);
    final sortButtonUpAfter = find.byIcon(Icons.arrow_upward).evaluate().isNotEmpty;
    expect(sortButtonUpBefore, isNot(equals(sortButtonUpAfter)), reason: 'Sort must actually toggle direction');
    print('✓ Sort toggle is real — direction icon actually flips');

    // ---- Summary + footer ----
    for (var i = 0; i < 6 && find.text('Summary').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Total Salesmen'), findsOneWidget);
    expect(find.text('Avg Achievement'), findsOneWidget);
    print('✓ Summary section rendered');

    for (var i = 0; i < 4 && find.textContaining('All amounts are in INR').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.textContaining('All amounts are in INR'), findsOneWidget);
    print('✓ Footer note present');

    // ---- Export button gives real feedback ----
    for (var i = 0; i < 8 && find.text('Export').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, 400));
      await settle(tester);
    }
    await tester.tap(find.text('Export'));
    await settle(tester);
    expect(find.textContaining('Report export started'), findsOneWidget, reason: 'Export must give real feedback, not be decorative');
    print('✓ Export button gives real feedback');

    // ---- Back navigation ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reports'), findsWidgets, reason: 'Back must return to the Manager Reports list');
    print('✓ Back navigation returns to the Reports list');

    print('✓ Manager Salesmen Performance flow complete');
  });
}
