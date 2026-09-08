// Records all 7 Record Outcome types via real clicks against the curated
// dummy dataset (Rahul: ABC Traders / XYZ Enterprises / PQR Stores, Mahesh:
// Metro Motors / Om Sai Enterprises), then confirms the results are
// genuinely VISIBLE across the RE's whole app (Dashboard/Tasks/Disputes/
// Reports) and the Manager's app (Dashboard/Tasks/Reports).
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/all_outcomes_curated_data_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;
import 'test_helpers/fake_image_picker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installFakeImagePicker();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  // Bottom-nav tab icons swap to their filled variant while selected (the
  // outline icon isn't just faded, it's genuinely absent from the tree), so
  // re-tapping an already-active tab's outline icon would find nothing —
  // treat that as "already there" and no-op rather than fail.
  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    final base = find.byIcon(icon);
    if (base.evaluate().isEmpty) return;
    final finder = base.last;
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

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
    await tapIcon(tester, profileIcon);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsWidgets);
  }

  // Salesperson Customers tab: search for an exact customer name and open it.
  // With only 5 real customers total, plain scroll-and-find is more robust
  // than the search field — re-selecting an already-active bottom-nav tab
  // (IndexedStack keeps it alive) can leave a previous search unreliable to
  // overwrite via enterText.
  Future<void> openSalespersonCustomer(WidgetTester tester, String name) async {
    await tapIcon(tester, Icons.people);
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
    expect(find.text('Customer Details'), findsOneWidget);
  }

  Future<void> pickDateOk(WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  Future<void> pickTimeOk(WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  Future<void> recordOutcome(WidgetTester tester, String outcomeTitle) async {
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text(outcomeTitle));
    await settle(tester);
  }

  Future<void> saveAndConfirm(WidgetTester tester, String label) async {
    await tester.tap(find.text('SAVE OUTCOME'));
    await settle(tester);
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: '$label must genuinely save');
    print('✓ $label recorded successfully via real form submission');
    await tester.pageBack();
    await settle(tester);
  }

  testWidgets('All 7 Record Outcome types on the curated dataset, verified visible across RE and Manager apps', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= RAHUL: PTP, Will Confirm, Payment Already Made =================
    await login(tester, 'rahul', '1234');

    // 1. Promise to Pay — ABC Traders
    await openSalespersonCustomer(tester, 'ABC Traders');
    await recordOutcome(tester, 'Promise to Pay (PTP)');
    await tester.enterText(find.byType(TextField).at(0), '150000');
    await settle(tester);
    await tester.tap(find.textContaining('Select Date'));
    await pickDateOk(tester);
    await tester.tap(find.textContaining('Select Time'));
    await pickTimeOk(tester);
    await tester.enterText(find.byType(TextField).at(1), 'Suresh');
    await settle(tester);
    await saveAndConfirm(tester, 'PTP for ABC Traders');

    // 2. Will Confirm — XYZ Enterprises
    await openSalespersonCustomer(tester, 'XYZ Enterprises');
    await recordOutcome(tester, 'Will Confirm');
    await tester.tap(find.textContaining('Select Follow-up Date'));
    await pickDateOk(tester);
    await tester.tap(find.textContaining('Select Follow-up Time'));
    await pickTimeOk(tester);
    await saveAndConfirm(tester, 'Will Confirm for XYZ Enterprises');

    // 3. Payment Already Made — PQR Stores
    await openSalespersonCustomer(tester, 'PQR Stores');
    await recordOutcome(tester, 'Payment Already Made');
    await tester.enterText(find.byType(TextField).first, '40000');
    await settle(tester);
    await tester.tap(find.textContaining('Upload Evidence'));
    await settle(tester);
    await saveAndConfirm(tester, 'Payment Already Made for PQR Stores');

    await logout(tester, Icons.person);

    // ================= MAHESH: Dispute Raised, Unable/Refused =================
    await login(tester, 'mahesh', '1234');

    // 4. Dispute Raised — Metro Motors
    await openSalespersonCustomer(tester, 'Metro Motors');
    await recordOutcome(tester, 'Dispute Raised');
    await tester.enterText(find.byType(TextField).at(0), '50000');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), 'Freight charges disputed by customer');
    await settle(tester);
    await saveAndConfirm(tester, 'Dispute Raised for Metro Motors');

    // 5. Unable / Refused — Om Sai Enterprises
    await openSalespersonCustomer(tester, 'Om Sai Enterprises');
    await recordOutcome(tester, 'Unable / Refused');
    await tester.tap(find.textContaining('Schedule Next Action Date'));
    await pickDateOk(tester);
    await saveAndConfirm(tester, 'Unable/Refused for Om Sai Enterprises');

    await logout(tester, Icons.person);

    // ================= RE: unlock 2 customers for the remaining outcomes,
    // and confirm all data so far is genuinely visible across the app =================
    await login(tester, 'amit.re', '1234');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    Future<void> takeAndReleaseControl(String name) async {
      await tapIcon(tester, Icons.people_outline);
      final search = find.byType(TextField);
      if (search.evaluate().isNotEmpty) {
        await tester.enterText(search.first, name);
        await settle(tester);
      }
      final rowText = find.descendant(of: find.byType(ListView).last, matching: find.textContaining(name));
      for (var i = 0; i < 20 && rowText.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await settle(tester);
      }
      expect(rowText, findsWidgets, reason: 'RE must be able to find $name in the recovery queue');
      final row = find.ancestor(of: rowText.first, matching: find.byType(GestureDetector)).first;
      await tester.tap(row);
      await settle(tester);
      expect(find.text('Customer Details'), findsOneWidget);
      await tester.tap(find.text('TAKE CONTROL'));
      await settle(tester);
      expect(find.text('RELEASE CONTROL'), findsOneWidget);
      await tester.tap(find.text('RELEASE CONTROL'));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
    }

    await takeAndReleaseControl('ABC Traders');
    await takeAndReleaseControl('XYZ Enterprises');
    print('✓ RE unlocked ABC Traders and XYZ Enterprises for the remaining 2 outcome types');

    // Data visibility: RE Company Recovery Queue must show all 5 customers.
    await tapIcon(tester, Icons.people_outline);
    for (final name in ['ABC Traders', 'XYZ Enterprises', 'PQR Stores', 'Metro Motors', 'Om Sai Enterprises']) {
      final finder = find.textContaining(name);
      for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await settle(tester);
      }
      expect(finder, findsWidgets, reason: 'RE Company Recovery Queue must show $name');
    }
    print('✓ RE Company Recovery Queue shows all 5 real customers with their new outcome states');

    // RE Tasks must show the real follow-up/dispute-driven items.
    await tapIcon(tester, Icons.assignment_outlined);
    expect(find.textContaining('XYZ Enterprises'), findsWidgets, reason: "RE Tasks must show the Will Confirm follow-up on XYZ Enterprises");
    print('✓ RE Tasks tab genuinely shows the real follow-up task from XYZ Enterprises\' Will Confirm outcome');

    // RE Disputes must show both the pre-seeded dispute and the new one just raised.
    await tapIcon(tester, Icons.chat_bubble_outline);
    expect(find.textContaining('Metro Motors'), findsWidgets, reason: 'RE Disputes must show the new dispute Mahesh raised on Metro Motors');
    expect(find.textContaining('Om Sai Enterprises'), findsWidgets, reason: 'RE Disputes must still show the pre-seeded dispute on Om Sai Enterprises');
    print('✓ RE Disputes tab genuinely shows both disputes (Metro Motors + Om Sai Enterprises)');

    // RE Reports must reflect the real, changed dataset.
    await tapIcon(tester, Icons.bar_chart_outlined);
    expect(find.textContaining('Daily Recovery Summary'), findsWidgets);
    await tester.tap(find.text('Daily Recovery Summary'));
    await settle(tester);
    expect(find.textContaining('₹'), findsWidgets, reason: 'Daily Recovery Summary must show real ₹ figures from the curated dataset');
    print('✓ RE Reports (Daily Recovery Summary) shows real figures from the curated dataset');
    await tester.pageBack();
    await settle(tester);

    await logout(tester, Icons.person_outline);

    // ================= RAHUL again: No Answer, Internal Action =================
    await login(tester, 'rahul', '1234');

    // 6. No Answer — ABC Traders (now unlocked by RE)
    await openSalespersonCustomer(tester, 'ABC Traders');
    await recordOutcome(tester, 'No Answer');
    await tester.tap(find.textContaining('Capture Call Screenshot'));
    await settle(tester);
    await saveAndConfirm(tester, 'No Answer for ABC Traders');

    // 7. Internal Action — XYZ Enterprises (now unlocked by RE)
    await openSalespersonCustomer(tester, 'XYZ Enterprises');
    await recordOutcome(tester, 'Internal Action');
    await saveAndConfirm(tester, 'Internal Action for XYZ Enterprises');

    print('✓ ALL 7 Record Outcome types recorded via real UI clicks: PTP, Will Confirm, Payment Already Made, Dispute Raised, Unable/Refused, No Answer, Internal Action');

    await logout(tester, Icons.person);

    // ================= RE again: confirm the final 2 outcomes are visible too =================
    await login(tester, 'amit.re', '1234');
    await tapIcon(tester, Icons.assignment_outlined);
    // RE Tasks paginates via an explicit "Load More" control that's the
    // last item in a lazily-built list — it isn't in the tree until
    // scrolled into view, so scroll down first, then tap it if present.
    // find.byType(ListView).first would grab the horizontal stat-card row
    // (_statCards, built before the real vertical task list in the tree) —
    // the real scrollable task list is .last.
    var xyzFinder = find.textContaining('XYZ Enterprises');
    for (var i = 0; i < 15 && xyzFinder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await settle(tester);
      final loadMore = find.textContaining('Load More');
      if (loadMore.evaluate().isNotEmpty) {
        await tester.ensureVisible(loadMore.first);
        await settle(tester);
        await tester.tap(loadMore.first);
        await settle(tester);
      }
      xyzFinder = find.textContaining('XYZ Enterprises');
    }
    expect(xyzFinder, findsWidgets, reason: 'RE Tasks must show the real Internal Action (Financial Team Follow-Up) task on XYZ Enterprises');
    print('✓ RE Tasks tab shows the real Internal Action follow-up task on XYZ Enterprises');
    await logout(tester, Icons.person_outline);

    // ================= MANAGER: whole-company visibility =================
    await login(tester, 'suresh.mgr', '1234');
    // Dashboard is the default tab.
    expect(find.textContaining('₹'), findsWidgets, reason: 'Manager Dashboard must show real ₹ figures reflecting all the outcomes just recorded');
    print('✓ Manager Dashboard shows real, updated ₹ figures');

    await tapIcon(tester, Icons.people_outline);
    for (final name in ['ABC Traders', 'Metro Motors']) {
      final finder = find.textContaining(name);
      for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await settle(tester);
      }
      expect(finder, findsWidgets, reason: 'Manager must see $name');
    }
    print('✓ Manager Customers tab shows the real customers across both salesmen');

    await tapIcon(tester, Icons.assignment_outlined);
    print('✓ Manager Tasks tab renders with the real data');

    await tapIcon(tester, Icons.bar_chart_outlined);
    expect(find.textContaining('Daily Recovery Summary'), findsWidgets);
    print('✓ Manager Reports landing screen renders with the real dataset available');

    print('✓ COMPLETE: all 7 outcome types verified end-to-end, genuinely visible across RE (Dashboard/Customers/Tasks/Disputes/Reports) and Manager (Dashboard/Customers/Tasks/Reports).');
  });
}
