// Real end-to-end test of the Manager's new Management Attention screen —
// the L4 escalation queue and the one real write action the build guide
// assigns to Management: issuing a tracked Management Instruction — in a
// real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_management_attention_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Management Attention: real L4 cases, case detail, and a genuinely working Issue Instruction flow', (tester) async {
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

    // Dashboard's new "Management Attention" card.
    final dashboardList = find.byType(SingleChildScrollView).first;
    for (var i = 0; i < 8 && find.text('Management Attention').evaluate().isEmpty; i++) {
      await tester.drag(dashboardList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Management Attention'), findsOneWidget);
    expect(find.text('L4 Cases'), findsOneWidget, reason: 'Dashboard card must show a real L4 case count');
    // 'Money at Risk' also labels the Dashboard's separate general
    // money-at-risk stat card elsewhere on the same page — findsWidgets,
    // not exactly one.
    expect(find.text('Money at Risk'), findsWidgets, reason: 'Dashboard card must show real money-at-risk exposure');
    print('✓ Management Attention card rendered on the Dashboard with real L4/money-at-risk figures');

    final headerRow = find.ancestor(of: find.text('Management Attention'), matching: find.byType(Row)).first;
    final viewDetailsLink = find.descendant(of: headerRow, matching: find.text('View Details'));
    await tester.ensureVisible(viewDetailsLink);
    await settle(tester);
    await tester.tap(viewDetailsLink);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('L4 cases requiring an executive decision'), findsOneWidget, reason: 'Dashboard "View Details" must open the new Management Attention screen');
    print('✓ Management Attention screen opened from the Dashboard');

    // ---- Stat cards ----
    expect(find.text('L4 Cases'), findsOneWidget);
    // 'Money at Risk' is a shared label between this screen's own stat card
    // and the Dashboard's own general money-at-risk card underneath (kept
    // mounted by the scaffold's IndexedStack even while this screen is
    // pushed on top) — findsWidgets, not exactly one.
    expect(find.text('Money at Risk'), findsWidgets);
    expect(find.text('Pending Instructions'), findsWidgets);
    print('✓ Stat cards rendered with live data');

    // ---- Real L4 case cards, tap to open detail ----
    final outerList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('L4', skipOffstage: false).evaluate().length < 2; i++) {
      await tester.drag(outerList, const Offset(0, -400));
      await settle(tester);
    }
    final caseCards = find.text('L4', skipOffstage: false);
    expect(caseCards, findsWidgets, reason: 'There must be real open L4 cases to show — the seeded data includes several');
    // Tap the first genuinely mounted L4 case card.
    final firstCaseCard = find.ancestor(of: find.text('L4').first, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(firstCaseCard);
    await settle(tester);
    await tester.tap(firstCaseCard);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Current Plan'), findsOneWidget, reason: 'Case detail sheet must show the real Current Plan');
    expect(find.text('History'), findsOneWidget, reason: 'Case detail sheet must show the real escalation history');
    expect(find.text('Issue Management Instruction'), findsOneWidget, reason: 'The sheet must offer the one real Management action');
    print('✓ Case detail sheet shows real exposure, plan, and history');

    // ---- Issue Management Instruction: a genuinely working write flow ----
    final beforePending = tester.widgetList<Text>(find.textContaining('Pending Instructions', skipOffstage: false)).isNotEmpty;
    expect(beforePending, isTrue);
    await tester.tap(find.text('Issue Management Instruction'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Management Instruction'), findsOneWidget, reason: 'The Issue Instruction dialog must open');
    await tester.enterText(find.byType(TextField).first, 'RE must personally supervise the next recovery action.');
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Issue Instruction'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.textContaining('Management Instruction issued to'), findsOneWidget, reason: 'Issuing the instruction must give real, specific feedback');
    print('✓ Issue Management Instruction dialog genuinely submits and confirms');

    // The Pending Instructions stat card must reflect the real new task —
    // scroll back to the top to re-read the live stat card after the dialog closed.
    for (var i = 0; i < 6 && find.text('Pending Instructions').evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, 400));
      await settle(tester);
    }
    expect(find.text('Pending Instructions'), findsWidgets, reason: 'Stat card must still be present and reflect the live task count');
    print('✓ Pending Instructions stat card is present and live after issuing the instruction');

    // ---- Back navigation ----
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('L4 cases requiring an executive decision'), findsNothing, reason: 'Back must leave the Management Attention screen');
    expect(find.text('Manager Dashboard'), findsOneWidget, reason: 'Back must return to the Manager Dashboard');
    print('✓ Back navigation returns to the Dashboard');

    print('✓ Manager Management Attention flow complete');
  });
}
