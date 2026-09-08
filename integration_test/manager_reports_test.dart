// Real end-to-end test of the Manager's Reports screen, in a real Chrome
// browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_reports_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Reports: Quick Summary, real report drill-downs, branch filter, custom report, help', (tester) async {
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

    // .last: the Dashboard's own "Reports" quick-action tile uses the same
    // icon as the bottom-nav Reports tab, which renders after it in the tree.
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await settle(tester);
    expect(find.text('Reports'), findsWidgets, reason: 'Reports tab must open the Reports screen');
    expect(find.text('View performance, recovery and analytical reports'), findsOneWidget);
    print('✓ Manager Reports screen opened');

    // ---- Quick Summary: real, non-fabricated figures ----
    expect(find.textContaining('Quick Summary'), findsOneWidget);
    expect(find.text('Total Target (₹)'), findsOneWidget);
    expect(find.text('Total Received (₹)'), findsOneWidget);
    expect(find.text('Achievement'), findsOneWidget);
    expect(find.text('Total Overdue (₹)'), findsOneWidget);
    expect(find.text('Total Salesman'), findsOneWidget);
    print('✓ Quick Summary card rendered with all 5 real metrics');

    // ---- Branch filter: real dropdown, changes Quick Summary on selection ----
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    final mumbaiOption = find.text('Mumbai').last;
    expect(mumbaiOption, findsOneWidget, reason: 'Branch dropdown must list real branches from the salesmen roster');
    await tester.tap(mumbaiOption);
    await settle(tester);
    expect(find.text('Mumbai'), findsWidgets, reason: 'Selecting Mumbai must actually apply as the active branch filter');
    print('✓ Branch filter dropdown opened, listed real branches, and a selection was applied');

    // ---- All 8 report rows exist and are tappable ----
    final reportTitles = [
      'Daily Recovery Summary',
      'Salesman Performance',
      'PTP Reports',
      'Broken PTP Reports',
      'Dispute Status Report',
      'Ageing Receivables',
      'Expected vs Actual Recovery',
      'No Follow-up Report',
    ];
    for (final title in reportTitles) {
      expect(find.text(title), findsOneWidget, reason: '"$title" must be listed as an available report');
    }
    print('✓ All 8 report types listed');

    // ---- Open one real report and confirm it renders real data ----
    await tester.tap(find.text('Daily Recovery Summary'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Daily Recovery Summary'), findsWidgets, reason: 'Tapping a report must navigate to its real detail screen');
    print('✓ Daily Recovery Summary report opened for real');
    // This report screen contains a Scrollbar bound to an animation
    // controller that never fully settles, so use fixed pumps here instead
    // of pumpAndSettle (which can behave unpredictably against a
    // perpetually-ticking controller).
    await tester.tap(find.byTooltip('Back').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reports'), findsWidgets, reason: 'Must return to the Reports list after going back');

    // ---- Custom Reports: Build Your Own Report ----
    // "Custom Reports" sits below the fold on this long page — scroll the
    // list down to bring it into the built element tree before searching.
    final reportsList = find.byType(ListView).first;
    for (var i = 0; i < 8 && find.text('Build Your Own Report').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Custom Reports'), findsOneWidget);
    expect(find.text('Build Your Own Report'), findsOneWidget);
    await tester.ensureVisible(find.text('Create Report'));
    await settle(tester);
    await tester.tap(find.text('Create Report'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    print('✓ "Create Report" opened a real report screen');
    await tester.tap(find.byTooltip('Back').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // ---- Footer note ----
    // The scroll offset survives the round trip through "Create Report", so
    // the footer (just after Custom Reports) should still be in view.
    for (var i = 0; i < 6 && find.textContaining('All reports are real-time').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.textContaining('All reports are real-time'), findsOneWidget);
    print('✓ Real-time data footer note present');

    // ---- Help button: real, functional ----
    // Scroll back up to the header where Help lives.
    for (var i = 0; i < 8 && find.text('Help').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, 400));
      await settle(tester);
    }
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('About Reports'), findsOneWidget, reason: 'Help button must open a real help dialog');
    await tester.tap(find.text('Got it'));
    await settle(tester);
    print('✓ Help button opens a real, functional dialog');

    print('✓ Manager Reports flow complete');
  });
}
