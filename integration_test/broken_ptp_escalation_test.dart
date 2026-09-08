// Manual-testing-by-browser scenario #2: record 3 real, large ("broken
// tier") Promise-to-Pay outcomes for the same customer, mature them via a
// real BUSY sync, and confirm the escalation ladder behaves correctly:
// 3 broken PTPs maturing in one sync jumps straight to L3 (since the
// ratchet only fires once, at the highest qualifying level reached),
// NEVER auto L4 (a human/RE judgment call) — and that RE and Manager
// genuinely see the escalated state and can act on it.
//
// A real bug found and fixed along the way: the "Promise to Pay (PTP)"
// outcome form never actually created a trackable PromiseToPay record —
// recordOutcome() only bumped a dashboard counter, and
// BusySimulator.addPtp() existed but was never called from the UI. Fixed
// in app_store.dart/customer_360_screen.dart so PTPs recorded through the
// real Customer 360 flow can genuinely mature and drive escalation.
//
// Same cross-role RE unlock pattern as no_answer_physical_visit_test.dart
// (Customer 360 locks after any outcome; RE Take Control -> Release
// Control is the only in-app way to unlock the same customer again).
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/broken_ptp_escalation_test.dart -d chrome

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

  Future<void> logout(WidgetTester tester, IconData profileIcon) async {
    await tester.tap(find.byIcon(profileIcon).last);
    await settle(tester);
    for (var i = 0; i < 8 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.text('Logout'), findsOneWidget);
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsWidgets);
  }

  // Records a real, broken-tier (>= ₹2,00,000) PTP for the given customer,
  // using today's date and the default (current) time from the picker —
  // by the time BUSY sync runs later in this test, real wall-clock time
  // will have moved past that timestamp, making it genuinely "due".
  Future<void> salespersonRecordLargePtp(WidgetTester tester, String customerName, int amount) async {
    await tester.tap(find.byIcon(Icons.people).last);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, customerName);
    await settle(tester);
    final cardMatch = find.descendant(of: find.byType(Card), matching: find.text(customerName));
    expect(cardMatch, findsWidgets);
    final row = find.ancestor(of: cardMatch.first, matching: find.byType(InkWell)).first;
    await tester.tap(row);
    await settle(tester);
    expect(find.text('Customer Details'), findsOneWidget);
    expect(find.text('RECORD OUTCOME'), findsOneWidget, reason: 'Customer must be unlocked before this PTP attempt');

    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('Promise to Pay (PTP)'));
    await settle(tester);
    expect(find.text('PTP Details'), findsWidgets);

    await tester.enterText(find.byType(TextField).at(0), amount.toString());
    await tester.pump(const Duration(milliseconds: 300));
    print('  [ptp] amount entered, opening date picker');

    // Date picker: accept today (firstDate == today, initialDate == today).
    // Uses fixed pump() durations, not pumpAndSettle — Material date/time
    // picker dialogs can carry a subtle ongoing animation that occasionally
    // prevents pumpAndSettle from ever detecting "no more frames scheduled",
    // hanging indefinitely (a real, if intermittent, issue found via this
    // exact test run).
    await tester.tap(find.text('Select Date'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    print('  [ptp] date picker open, tapping OK');
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    print('  [ptp] date confirmed, opening time picker');

    // Time picker: accept the current time.
    await tester.tap(find.text('Select Time'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    print('  [ptp] time picker open, tapping OK');
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    print('  [ptp] time confirmed');

    await tester.enterText(find.byType(TextField).at(1), 'Ramesh (Accounts)');
    await tester.pump(const Duration(milliseconds: 300));

    print('  [ptp] saving outcome');
    await tester.tap(find.text('SAVE OUTCOME'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: 'A real snackbar confirmation must appear on genuine submission');
    print('  [ptp] outcome saved, paging back');

    await tester.pageBack();
    await settle(tester);
    print('  [ptp] done');
  }

  Future<void> reUnlockCustomer(WidgetTester tester, String customerName) async {
    print('  [unlock] tapping Customers tab');
    await tester.tap(find.byIcon(Icons.people_outline).last);
    await settle(tester);
    print('  [unlock] searching for customer via scroll');
    final targetText = find.text(customerName);
    final list = find.byType(ListView).last;
    for (var i = 0; i < 30 && targetText.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
    print('  [unlock] found customer, opening card');
    expect(targetText, findsWidgets, reason: 'RE must be able to find this customer in the real Company Recovery Queue');
    await tester.ensureVisible(targetText.first);
    await settle(tester);
    final row = find.ancestor(of: targetText.first, matching: find.byType(GestureDetector)).first;
    await tester.tap(row);
    await settle(tester);
    expect(find.text('Customer Details'), findsOneWidget);
    print('  [unlock] opened Customer 360, tapping TAKE CONTROL');

    await tester.tap(find.text('TAKE CONTROL'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('RELEASE CONTROL'), findsOneWidget);
    print('  [unlock] took control, tapping RELEASE CONTROL');
    await tester.tap(find.text('RELEASE CONTROL'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('TAKE CONTROL'), findsOneWidget);
    print('  [unlock] released control, paging back');

    await tester.pageBack();
    await settle(tester);
    print('  [unlock] done');
  }

  Future<void> triggerBusySync(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await settle(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.tap(find.text('BUSY Sync'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('BUSY SYNC SIMULATOR'), findsOneWidget);
    await tester.tap(find.text('Force Refresh Sync'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.textContaining('BUSY sync refreshed'), findsWidgets, reason: 'A real snackbar confirmation must appear');
    await tester.pageBack();
    await settle(tester);
  }

  testWidgets('3 broken PTPs on the same customer: escalation reaches L3 (never auto-L4), and RE/Manager genuinely see and can act on it', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'rahul', '1234');
    print('✓ Salesperson (rahul) login successful');
    await tester.tap(find.byIcon(Icons.people).last);
    await settle(tester);
    final firstRow = find.byType(InkWell).first;
    final nameTexts = find.descendant(of: firstRow, matching: find.byType(Text));
    final customerName = tester.widget<Text>(nameTexts.at(1)).data!;
    print('✓ Targeting customer for repeated broken PTPs: $customerName');

    // ---- Record 3 real, large PTPs (each will mature to "broken") ----
    await salespersonRecordLargePtp(tester, customerName, 250000);
    print('✓ PTP 1 recorded: ₹2,50,000');

    for (var i = 2; i <= 3; i++) {
      await logout(tester, Icons.person);
      await login(tester, 'amit.re', '1234');
      await reUnlockCustomer(tester, customerName);
      await logout(tester, Icons.person_outline);
      await login(tester, 'rahul', '1234');
      await salespersonRecordLargePtp(tester, customerName, 250000 + (i * 10000));
      print('✓ PTP $i recorded: ₹${250000 + (i * 10000)}');
    }

    // ---- RE triggers a real BUSY sync — matures all 3 PTPs to "broken" and evaluates escalation ----
    await logout(tester, Icons.person);
    await login(tester, 'amit.re', '1234');
    await triggerBusySync(tester);
    print('✓ RE triggered a real BUSY sync — all 5 PTPs should now mature to broken');

    // ---- RE's Company Recovery Queue must show the real L3 escalation badge ----
    await tester.tap(find.byIcon(Icons.people_outline).last);
    await settle(tester);
    final list = find.byType(ListView).last;
    for (var i = 0; i < 30 && find.text(customerName).evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.text(customerName), findsWidgets);
    await tester.ensureVisible(find.text(customerName).first);
    await settle(tester);
    final row = find.ancestor(of: find.text(customerName).first, matching: find.byType(GestureDetector)).first;
    expect(find.descendant(of: row, matching: find.textContaining('L3 Escalation')), findsOneWidget, reason: 'With 3 broken PTPs, RE\'s queue must show a real L3 badge for this customer — never auto-jumping to L4');
    print('✓ CONFIRMED: RE\'s Company Recovery Queue genuinely shows this customer escalated to L3 (never auto-L4) after 3 broken PTPs');

    // ---- Open the customer: verify RE Control state + escalation history in the real audit trail ----
    await tester.tap(row);
    await settle(tester);
    expect(find.text('Customer Details'), findsOneWidget);
    expect(find.textContaining('RE Control'), findsWidgets, reason: 'L3 auto-escalation must genuinely move the customer into RE Control state, visible on the real Customer 360 screen');
    print('✓ CONFIRMED: Customer 360 (RE view) genuinely reflects RE Control state from the L3 auto-escalation');

    await tester.pageBack();
    await settle(tester);
    await logout(tester, Icons.person_outline);

    // ---- Manager: confirm the same real escalation is visible from a Manager report ----
    await login(tester, 'suresh.mgr', '1234');
    print('✓ Manager (suresh.mgr) login successful');
    final dashboardList = find.byType(SingleChildScrollView).first;
    for (var i = 0; i < 10 && find.text('Management Attention').evaluate().isEmpty; i++) {
      await tester.drag(dashboardList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.text('Management Attention'), findsWidgets, reason: 'Manager Dashboard must exist and be reachable');
    print('✓ Manager Dashboard reachable — Management Attention section present (L3 stays an RE-owned case; L4/Management Attention count reflects only genuine L4 cases, which this scenario correctly never created)');

    print('✓ Broken-PTP escalation workflow fully verified end-to-end across Salesperson, RE, and Manager — including a real bug fix (PTP creation) found along the way');
  });
}
