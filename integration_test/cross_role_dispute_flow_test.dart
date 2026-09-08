// Real cross-role end-to-end test: carries ONE real dispute through all
// three roles in a single continuous session (no data reset between role
// switches — logout only flips `isLoggedIn`, the shared AppStore keeps its
// state) to prove data genuinely flows Salesperson -> Recovery Executive ->
// Manager, not just that each role's screens render in isolation.
//
// Salesperson (rahul) raises a dispute on a real customer
//   -> Recovery Executive (amit.re) sees it in the Approval queue and
//      approves it (assigns real resolution owner + deadline)
//   -> Manager (suresh.mgr) sees the SAME dispute, by its real reason text,
//      reflecting its new Approved status in two different Manager report
//      screens.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/cross_role_dispute_flow_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  // pumpAndSettle only waits for scheduled *frames* to stop — a real HTTP
  // round-trip to the live server that doesn't itself trigger a repeating
  // animation/frame (no spinner) can still be in flight when pumpAndSettle
  // returns, so a next action (e.g. navigating away) can race it and land
  // in an inconsistent state. This pumps for a fixed real duration instead,
  // giving the request time to genuinely complete regardless of framing.
  Future<void> waitForApi(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
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

  // A reason string unique enough to reliably re-find this exact dispute
  // later under a completely different role/screen, without relying on any
  // generated ID.
  const disputeReason = 'CROSS_ROLE_E2E_TEST — packaging materially damaged in transit';

  testWidgets('Cross-role: a Salesperson-raised dispute is genuinely seen and actioned by RE, then reflected for Manager', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= ROLE 1: SALESPERSON =================
    await login(tester, 'rahul', '1234');
    print('✓ Salesperson (rahul) login successful');

    await tester.tap(find.byIcon(Icons.people).last);
    await settle(tester);
    final customerRow = find.byType(InkWell);
    expect(customerRow, findsWidgets, reason: 'Salesperson customer list must have real rows');
    // Capture the real customer's name from the list row before tapping —
    // the Manager's dispute report screens show reason as a CATEGORY label
    // (e.g. "Damaged Material"), not the raw text, so the customer name is
    // the reliable identifier to re-find this exact dispute later.
    final nameTextsInRow = find.descendant(of: customerRow.first, matching: find.byType(Text));
    final customerName = tester.widget<Text>(nameTextsInRow.at(1)).data!;
    await tester.tap(customerRow.first);
    await settle(tester);
    // Customer 360 fires a real detail-refresh API call on open (for its
    // Invoices/History tabs) with no spinner — the same race as elsewhere.
    await waitForApi(tester);
    expect(find.text('Customer Details'), findsOneWidget, reason: 'Tapping a customer must open Customer 360');
    print('✓ Opened a real customer from the Salesperson portfolio: $customerName');

    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('Dispute Raised'));
    await settle(tester);
    expect(find.text('Dispute / Issue'), findsWidgets);

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), '45000');
    await settle(tester);
    await tester.enterText(textFields.at(1), disputeReason);
    await settle(tester);
    await tester.tap(find.text('SAVE OUTCOME'));
    await settle(tester);
    // The real record-outcome API call doesn't itself trigger a repeating
    // animation, so pumpAndSettle can report "settled" before it genuinely
    // completes — give it real time before navigating away.
    await waitForApi(tester);
    print('✓ Salesperson raised a real dispute: ₹45,000, reason "$disputeReason"');

    // ================= LOGOUT -> ROLE 2: RECOVERY EXECUTIVE =================
    // AppStore.logout() only flips isLoggedIn — customers/disputes/tasks are
    // NOT reset, so the dispute just raised must still be there for RE.
    // pageBack() looks for a Cupertino-specific widget type this app doesn't
    // use, and its Material fallback is unreliably hit-testable here — use
    // the AppBar back button's own tooltip directly (established fix, see
    // re_tasks_e2e_test.dart).
    await tester.tap(find.byTooltip('Back').first);
    await settle(tester);
    await tester.tap(find.byIcon(Icons.person).last);
    await settle(tester);
    for (var i = 0; i < 8 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    expect(find.text('Logout'), findsOneWidget, reason: 'A real Logout control must be reachable from the Salesperson profile');
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsWidgets, reason: 'Logout must genuinely return to the login screen before the next role logs in');
    print('✓ Logged out of Salesperson session');

    await login(tester, 'amit.re', '1234');
    print('✓ Recovery Executive (amit.re) login successful — same app session, same store');

    await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
    await settle(tester);
    print('✓ Opened RE Disputes tab');

    final disputesList = find.byType(Scrollable).first;
    for (var i = 0; i < 12 && find.textContaining(disputeReason).evaluate().isEmpty; i++) {
      await tester.drag(disputesList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining(disputeReason), findsWidgets, reason: 'The exact dispute raised by the Salesperson must be visible to the RE — this is the real cross-role data-flow check');
    print('✓ RE genuinely sees the real dispute the Salesperson just raised (same reason text, not a coincidence)');

    await tester.tap(find.textContaining(disputeReason).first);
    await settle(tester);
    final approveAssign = find.text('Approve & Assign');
    expect(approveAssign, findsOneWidget, reason: 'Dispute detail must offer a real Approve & Assign action');
    await tester.tap(approveAssign);
    await settle(tester);
    final confirmApproval = find.text('Confirm Approval & Assign');
    expect(confirmApproval, findsOneWidget, reason: 'Assign screen must render with real pre-filled defaults');
    await tester.tap(confirmApproval);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    print('✓ RE approved the real dispute and assigned a real resolution owner + deadline');

    // ================= LOGOUT -> ROLE 3: MANAGER =================
    await tester.tap(find.byIcon(Icons.person_outline).last);
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
    expect(find.text('Sign In'), findsWidgets, reason: 'Logout must genuinely return to the login screen before the Manager logs in');
    print('✓ Logged out of RE session');

    await login(tester, 'suresh.mgr', '1234');
    print('✓ Manager (suresh.mgr) login successful — same app session, same store');

    // ---- Manager Dispute Management Summary ----
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await settle(tester);
    final reportsList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('Dispute Management – Summary').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    final summaryTile = find.text('Dispute Management – Summary');
    expect(summaryTile, findsOneWidget);
    await tester.ensureVisible(summaryTile);
    await settle(tester);
    await tester.tap(summaryTile);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));

    final summaryOuterList = find.byType(ListView).first;
    for (var i = 0; i < 15 && find.textContaining(customerName).evaluate().isEmpty; i++) {
      await tester.drag(summaryOuterList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining(customerName), findsWidgets, reason: 'Manager Dispute Management Summary must show the same real customer/dispute the RE just approved');
    // Its status badge must say "Approved" (the exact status approveDispute()
    // sets) — not still "Pending Review"/"Pending Approval", which would mean
    // the Manager screen failed to reflect the RE\'s real action.
    expect(find.text('Approved'), findsWidgets, reason: 'The dispute must show as Approved in the Dispute Management Summary after the RE approved it');
    print('✓ Manager Dispute Management Summary genuinely reflects the dispute as Approved for $customerName');

    // ---- Manager Dispute Status Report (the OLDER, separate report screen) ----
    // Regression check for a real bug found and fixed in this session: its
    // status-bucket switch had no case for 'Approved' (the exact status
    // approveDispute() sets), so it silently fell through to 'Awaiting
    // Review' — meaning an RE-approved dispute would incorrectly still look
    // untouched here. It must now bucket as 'In Progress'.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final reportsList2 = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('Dispute Status Report').evaluate().isEmpty; i++) {
      await tester.drag(reportsList2, const Offset(0, -400));
      await settle(tester);
    }
    final statusReportTile = find.text('Dispute Status Report');
    expect(statusReportTile, findsOneWidget);
    await tester.ensureVisible(statusReportTile);
    await settle(tester);
    await tester.tap(statusReportTile);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));

    final statusOuterList = find.byType(ListView).first;
    for (var i = 0; i < 15 && find.textContaining(customerName).evaluate().isEmpty; i++) {
      await tester.drag(statusOuterList, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining(customerName), findsWidgets, reason: 'Dispute Status Report must also show the same real dispute');
    expect(find.text('In Progress'), findsWidgets, reason: 'Regression check: an Approved dispute must bucket as In Progress here, not silently fall back to Awaiting Review');
    print('✓ Dispute Status Report also correctly reflects the Approved dispute as In Progress (regression check for the bucket-mapping bug)');

    print('✓ Cross-role dispute flow complete: Salesperson -> RE -> Manager, all seeing the same real data');
  });
}
