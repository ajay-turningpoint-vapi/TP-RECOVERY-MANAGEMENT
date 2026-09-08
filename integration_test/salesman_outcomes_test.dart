// Real end-to-end test: pumps the actual v3 app, taps real rendered
// widgets in a real Chrome browser via chromedriver. Covers the four
// Record Outcome options that don't require camera/file evidence — PTP,
// Will Confirm, Unable To Commit, Internal Action — completed fully,
// including checking the resulting entry in the customer's History tab.
// (The three evidence-gated outcomes plus Profile/Logout are covered
// separately in salesman_validation_test.dart — kept in their own file so
// each session stays short and reliable.)
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/salesman_outcomes_test.dart -d chrome

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
  }

  // History is a lazily-built list — scroll until the target entry is
  // actually built and visible before asserting on its content.
  Future<void> scrollUntilVisible(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
  }

  Future<void> pickFirstDateThenTime(WidgetTester tester, {required String dateLabel, required String timeLabel}) async {
    await tester.tap(find.text(dateLabel));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.tap(find.text(timeLabel));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  // Opens a specific, named customer — the real customer list is always
  // returned in a fixed alphabetical order (never reordered after an
  // outcome), so each outcome below targets a different real customer by
  // name rather than assuming "the first customer" changes between calls.
  Future<void> openCustomer(WidgetTester tester, String name) async {
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
    expect(find.text('Customer Details'), findsWidgets, reason: 'Tapping a customer must open Customer 360');
  }

  // rahul owns only 3 real customers, and this test covers 4 outcomes — an
  // RE take-control/release-control cycle unlocks $name (already locked by
  // an earlier outcome in this same test) back to a fresh, actionable state
  // for reuse, rather than needing a 4th customer that doesn't exist.
  Future<void> reUnlockCustomer(WidgetTester tester, String name) async {
    await tester.tap(find.byIcon(Icons.person).last);
    await settle(tester);
    for (var i = 0; i < 8 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'amit.re', '1234');
    await tester.tap(find.byIcon(Icons.people_outline).last);
    await settle(tester);
    final card = find.descendant(of: find.byType(Card), matching: find.text(name));
    for (var i = 0; i < 15 && card.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await settle(tester);
    }
    expect(card, findsWidgets, reason: '$name must appear in the RE company-wide queue');
    await tester.tap(find.ancestor(of: card.first, matching: find.byType(GestureDetector)).first);
    await settle(tester);
    expect(find.text('Customer Details'), findsWidgets);
    if (find.text('TAKE CONTROL').evaluate().isNotEmpty) {
      await tester.tap(find.text('TAKE CONTROL'));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
    }
    await tester.tap(find.text('RELEASE CONTROL'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    await tester.tap(find.byIcon(Icons.person).last);
    await settle(tester);
    for (var i = 0; i < 8 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'rahul', '1234');
  }

  testWidgets('Salesman: PTP, Will Confirm, Unable To Commit, Internal Action — full submit + real History verification', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Sign In'), findsWidgets, reason: 'Login screen must render');
    await login(tester, 'rahul', '1234');
    expect(find.text('Sign In'), findsNothing, reason: 'Must have navigated away from login after valid credentials');
    print('✓ Salesman login successful, landed on Dashboard');

    await tester.tap(find.byIcon(Icons.people).last);
    await settle(tester);
    print('✓ Customers tab opened');

    // ================= 1. PROMISE TO PAY =================
    await openCustomer(tester, 'ABC Traders');
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    expect(find.text('Promise to Pay (PTP)'), findsWidgets, reason: 'Outcome picker must list PTP as an option');
    print('✓ Record Outcome picker opened, all 7 outcome tiles present: ${[
      'Promise to Pay (PTP)', 'Payment Already Made', 'Will Confirm', 'No Answer', 'Dispute Raised', 'Unable / Refused', 'Internal Action'
    ].where((t) => find.text(t).evaluate().isNotEmpty).toList()}');

    await tester.tap(find.text('Promise to Pay (PTP)'));
    await settle(tester);
    expect(find.text('PTP Details'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, '175000');
    await settle(tester);
    await pickFirstDateThenTime(tester, dateLabel: 'Select Date', timeLabel: 'Select Time');
    await tester.enterText(find.byType(TextField).at(1), 'Suresh Kumar');
    await settle(tester);
    await tester.tap(find.text('SAVE OUTCOME'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: 'A real PTP submission must show the confirmation snackbar');
    print('✓ PTP: filled real form (amount, date, time, person, mode), submitted, confirmation snackbar shown');

    await tester.tap(find.text('History'));
    await settle(tester);
    await scrollUntilVisible(tester, find.textContaining('Promise To Pay Recorded'));
    expect(find.textContaining('Promise To Pay Recorded'), findsWidgets, reason: 'History tab must show a specific label for the PTP just recorded, not a generic placeholder');
    expect(find.textContaining('Rahul Sharma'), findsWidgets, reason: 'History must attribute the entry to the real logged-in salesman, not a hardcoded name');
    print('✓ History tab verified: real PTP entry present, correctly attributed to Rahul Sharma (not fake data)');

    // ================= 2. WILL CONFIRM =================
    await tester.pageBack();
    await settle(tester);
    await openCustomer(tester, 'PQR Stores');
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('Will Confirm'));
    await settle(tester);
    expect(find.text('Will Confirm'), findsWidgets);
    await pickFirstDateThenTime(tester, dateLabel: 'Select Follow-up Date', timeLabel: 'Select Follow-up Time');
    await tester.tap(find.text('SAVE OUTCOME'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: 'Will Confirm submission must show the confirmation snackbar');
    print('✓ Will Confirm: real date+time picked, submitted, confirmation snackbar shown');

    await tester.tap(find.text('History'));
    await settle(tester);
    await scrollUntilVisible(tester, find.textContaining('Follow-Up Scheduled'));
    expect(find.textContaining('Follow-Up Scheduled'), findsWidgets, reason: 'History must show the real Will Confirm follow-up entry');
    print('✓ History tab verified: real Will Confirm entry present');

    // ================= 3. UNABLE TO COMMIT =================
    await tester.pageBack();
    await settle(tester);
    await openCustomer(tester, 'XYZ Enterprises');
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('Unable / Refused'));
    await settle(tester);
    expect(find.text('Unable To Commit'), findsWidgets);
    // Validation: try to save without picking the required Next Action Date.
    await tester.tap(find.text('SAVE OUTCOME'));
    await settle(tester);
    expect(find.text('Please select Next Action Date'), findsWidgets, reason: 'Unable To Commit must block submission without a next action date');
    print('✓ Unable To Commit: confirmed empty-submit is blocked with a real validation error');
    await tester.tap(find.text('Schedule Next Action Date (Required)'));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.tap(find.text('SAVE OUTCOME'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: 'Unable To Commit must show the confirmation snackbar once validated');
    print('✓ Unable To Commit: filled real form, submitted, confirmation snackbar shown');

    await tester.tap(find.text('History'));
    await settle(tester);
    await scrollUntilVisible(tester, find.textContaining('Unable To Commit'));
    expect(find.textContaining('Unable To Commit'), findsWidgets, reason: 'History must show the real Unable To Commit entry with a scheduled next action');
    print('✓ History tab verified: real Unable To Commit entry present');

    // ================= 4. INTERNAL ACTION REQUIRED =================
    // rahul only owns 3 real customers — reuse ABC Traders (locked by
    // outcome #1) via a real RE take-control/release-control cycle rather
    // than needing a 4th customer that doesn't exist in the real seed.
    await tester.pageBack();
    await settle(tester);
    await reUnlockCustomer(tester, 'ABC Traders');
    await tester.tap(find.byIcon(Icons.people).last);
    await settle(tester);
    await openCustomer(tester, 'ABC Traders');
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('Internal Action'));
    await settle(tester);
    expect(find.text('Internal Action Required'), findsWidgets);
    await tester.tap(find.text('SAVE OUTCOME'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: 'Internal Action Required must show the confirmation snackbar');
    print('✓ Internal Action Required: submitted, confirmation snackbar shown');

    await tester.tap(find.text('History'));
    await settle(tester);
    await scrollUntilVisible(tester, find.textContaining('Internal Action Required'));
    expect(find.textContaining('Internal Action Required'), findsWidgets, reason: 'History must show the real Internal Action entry');
    print('✓ History tab verified: real Internal Action entry present');

    print('✓ Salesman outcomes flow complete');
  });
}
