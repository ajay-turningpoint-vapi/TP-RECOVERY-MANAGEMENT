// Verifies RE Disputes bucketing is genuinely correct after a real approval
// action, and that the Reports screen's dead 3-dot button is really gone.
//
// Real bugs fixed and covered here:
//   - An Approved dispute used to fall through to the "OPEN" bucket in the
//     RE Disputes screen's own hand-rolled status->bucket mapping, which had
//     drifted out of sync with the store's canonical mapping.
//   - The Reports screen's 3-dot icon did nothing (onPressed: () {}).
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/re_disputes_reports_test.dart -d chrome

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

  testWidgets('RE Disputes bucketing is correct after approval, and Reports has no dead 3-dot button', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'amit.re', '1234');

    // ================= Reports: 3-dot button must be gone =================
    await tester.tap(find.byIcon(Icons.bar_chart_outlined));
    await settle(tester);
    expect(find.text('Reports'), findsWidgets);
    expect(find.byIcon(Icons.more_vert), findsNothing, reason: 'The dead 3-dot button (onPressed: () {}) must be removed from Reports');
    expect(find.byIcon(Icons.menu), findsOneWidget, reason: 'The hamburger icon must remain — it is the only entry point to Approvals/Escalations/Notifications/5PM Control/Search');
    print('✓ Reports header: dead 3-dot button removed, hamburger menu kept');

    // ================= Disputes: approve, then verify bucketing =================
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await settle(tester);
    expect(find.textContaining('OPEN'), findsWidgets, reason: 'Disputes screen must show real bucket tabs');

    // The seeded dispute (Om Sai Enterprises, D_001) starts as Pending
    // Approval -> OPEN bucket. Open it and approve it.
    final disputeCard = find.textContaining('Om Sai Enterprises');
    expect(disputeCard, findsWidgets, reason: 'The seeded Om Sai Enterprises dispute must be visible');
    final cardTap = find.ancestor(of: disputeCard.first, matching: find.byType(GestureDetector)).first;
    await tester.tap(cardTap);
    await settle(tester);
    expect(find.text('Approve & Assign'), findsOneWidget, reason: 'Dispute Details must offer a real Approve & Assign action');
    await tester.tap(find.text('Approve & Assign'));
    await settle(tester);
    expect(find.text('Confirm Approval & Assign'), findsOneWidget, reason: 'Must reach the real Approve & Assign form');
    await tester.tap(find.text('Confirm Approval & Assign'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Back on the list: the now-Approved dispute must show under IN
    // PROGRESS, not OPEN — this is the exact bucketing bug that was fixed.
    expect(find.textContaining('IN PROGRESS'), findsWidgets, reason: 'Disputes screen must have an IN PROGRESS bucket');
    final inProgressTab = find.ancestor(of: find.textContaining('IN PROGRESS').first, matching: find.byType(GestureDetector)).first;
    await tester.tap(inProgressTab);
    await settle(tester);
    expect(find.textContaining('Om Sai Enterprises'), findsWidgets, reason: 'The approved dispute must appear under IN PROGRESS, not be lost in OPEN — this is the exact bucket-mapping bug that was fixed');
    print('✓ Approved dispute is genuinely bucketed as IN PROGRESS, not OPEN');

    final openTab = find.ancestor(of: find.textContaining('OPEN').first, matching: find.byType(GestureDetector)).first;
    await tester.tap(openTab);
    await settle(tester);
    expect(find.textContaining('Om Sai Enterprises'), findsNothing, reason: 'The approved dispute must no longer appear under OPEN');
    print('✓ Approved dispute no longer appears under OPEN');

    print('✓ COMPLETE: RE Disputes bucketing is correct, and the Reports header is decluttered.');
  });
}
