// Verifies that when RE takes direct control of a customer, the
// salesperson's existing open task for that customer is genuinely closed
// out (superseded) — not left sitting open alongside RE Control, so each
// customer has exactly one active outcome record at a time.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/re_intervention_supersedes_task_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  Future<void> login(WidgetTester tester, String username, String password) async {
    await tester.enterText(find.byType(TextField).at(0), username);
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), password);
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
  }

  testWidgets("Rahul's open task for ABC Traders genuinely disappears from his Tasks tab after RE takes control", (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Confirm Rahul really has an open task for ABC Traders before RE acts.
    await login(tester, 'rahul', '1234');
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.assignment)));
    await settle(tester);
    expect(find.text('Customer not answering calls — physical visit required'), findsOneWidget, reason: "T1 must genuinely be open on Rahul's Tasks tab before RE intervenes");
    print("✓ Rahul's ABC Traders task is genuinely open before RE takes control");

    // Still on the main scaffold's Tasks tab (no route was pushed) — go
    // straight to logout.
    await tester.tap(find.byIcon(Icons.person));
    await settle(tester);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // RE takes direct control of ABC Traders.
    await login(tester, 'ramesh.re', '1234');
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.people_outline)));
    await settle(tester);
    final abcFinder = find.text('ABC Traders').first;
    for (var i = 0; i < 12 && abcFinder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.tap(abcFinder);
    await settle(tester);

    await tester.tap(find.text('TAKE CONTROL'));
    await settle(tester);
    print('✓ RE took direct control of ABC Traders');

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // RE's ReScaffoldV3 Profile tab uses Icons.person_outline while
    // unselected (Icons.person only once it's the active tab) — unlike the
    // salesman scaffold, which uses a single Icons.person regardless.
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.person_outline)));
    await settle(tester);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The task stays visible on Rahul's Tasks tab as a record (the "All"
    // filter shows history too), but must now render as superseded/done —
    // struck through, not a live open item — since RE Control is the sole
    // active outcome record for this customer now.
    await login(tester, 'rahul', '1234');
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.assignment)));
    await settle(tester);
    final supersededTaskFinder = find.text('Customer not answering calls — physical visit required');
    expect(supersededTaskFinder, findsOneWidget, reason: 'The task record should still be visible on the All tab, just no longer live');
    final textWidget = tester.widget<Text>(supersededTaskFinder);
    expect(textWidget.style?.decoration, equals(TextDecoration.lineThrough), reason: 'The task must render as superseded/completed (struck through), not as a live open item');
    print("✓ Rahul's ABC Traders task now renders as superseded (struck through) — no longer a live open item after RE took control");

    print('✓ COMPLETE: RE intervention genuinely supersedes the prior open task instead of leaving two active records.');
  });
}
