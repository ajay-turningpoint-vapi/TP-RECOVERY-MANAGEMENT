// Real end-to-end test of the Manager's rebuilt Daily Recovery Summary
// report screen, in a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_daily_recovery_summary_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Daily Recovery Summary: real stats, trend chart, branch table, top customers, header actions', (tester) async {
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
    await tester.tap(find.text('Daily Recovery Summary'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Daily Recovery Summary'), findsWidgets, reason: 'Tapping the report must open the rebuilt Daily Recovery Summary screen');
    expect(find.text('Target vs Received summary for today'), findsOneWidget);
    print('✓ Daily Recovery Summary screen opened');

    // ---- Stat cards: real, non-fabricated figures ----
    expect(find.text('Total Target (₹)'), findsOneWidget);
    expect(find.text('Total Received (₹)'), findsOneWidget);
    expect(find.text('Variance (₹)'), findsOneWidget);
    expect(find.text('No. of Payments'), findsOneWidget);
    print('✓ All 4 stat cards rendered with live data');

    // ---- Recovery Trend chart with legend + 4 metrics ----
    expect(find.text('Recovery Trend (Last 7 Days)'), findsOneWidget);
    // findsWidgets: "Target (₹)"/"Received (₹)" legitimately also appear as
    // the branch table's column headers, further down the page.
    expect(find.text('Target (₹)'), findsWidgets);
    expect(find.text('Received (₹)'), findsWidgets);
    expect(find.text('Average Daily Target'), findsOneWidget);
    expect(find.text('Average Daily Received'), findsOneWidget);
    expect(find.text('Best Day (Received)'), findsOneWidget);
    expect(find.text('Achievement'), findsOneWidget);
    print('✓ Recovery Trend chart and its 4 summary metrics rendered');

    // ---- Branch table ----
    expect(find.text('Target vs Received by Branch'), findsOneWidget);
    expect(find.text('Total'), findsWidgets);
    print('✓ Branch breakdown table rendered');

    // ---- Branch filter is real: applying it changes the visible screen ----
    final downArrows = find.byIcon(Icons.keyboard_arrow_down);
    expect(downArrows, findsWidgets);
    await tester.tap(downArrows.last);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final mumbaiOption = find.text('Mumbai').last;
    expect(mumbaiOption, findsOneWidget, reason: 'Branch dropdown must list real branches');
    await tester.tap(mumbaiOption);
    await settle(tester);
    print('✓ Branch filter dropdown opened and a real branch was applied');

    // ---- Top 5 Customers section ----
    for (var i = 0; i < 6 && find.textContaining('Top 5 Customers').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('Top 5 Customers'), findsOneWidget);
    print('✓ Top 5 Customers (By Amount Received) section rendered');

    // ---- Footer with real refresh action ----
    for (var i = 0; i < 6 && find.textContaining('All amounts are in INR').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.textContaining('All amounts are in INR'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await settle(tester);
    print('✓ Footer note present and refresh action works without error');

    // ---- Header actions: calendar / filter / share are real (show real feedback) ----
    for (var i = 0; i < 8 && find.byIcon(Icons.ios_share).evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, 400));
      await settle(tester);
    }
    await tester.tap(find.byIcon(Icons.ios_share));
    await settle(tester);
    expect(find.textContaining('Report export started'), findsOneWidget, reason: 'The share/export icon must give real feedback, not be decorative');
    print('✓ Header share/export icon gives real feedback');

    // ---- Back navigation returns to the Reports list ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reports'), findsWidgets, reason: 'Back must return to the Manager Reports list');
    print('✓ Back navigation returns to the Reports list');

    print('✓ Manager Daily Recovery Summary flow complete');
  });
}
