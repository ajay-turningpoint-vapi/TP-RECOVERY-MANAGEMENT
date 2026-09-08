// Verifies the RE Dispute Details and Approve & Assign screens genuinely
// show their content using the DEFAULT find() (skipOffstage: true) — the
// same finder behavior any other test in this app relies on, and a real
// proxy for "is this actually visible."
//
// Real bug fixed: both screens used `ListView(children: [Center(...)])` —
// a ListView (list widget) wrapping a single giant non-list child — which
// is a known Flutter anti-pattern. Switched to the idiomatic
// SingleChildScrollView, which is the correct widget for a single
// scrollable content block.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/dispute_details_content_test.dart -d chrome

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

  testWidgets('RE Dispute Details and Approve & Assign screens genuinely show their content', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'amit.re', '1234');

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await settle(tester);

    final openTab = find.ancestor(of: find.textContaining('OPEN').first, matching: find.byType(GestureDetector)).first;
    await tester.tap(openTab);
    await settle(tester);

    final disputeCard = find.textContaining('Om Sai Enterprises');
    expect(disputeCard, findsWidgets);
    final cardTap = find.ancestor(of: disputeCard.first, matching: find.byType(GestureDetector)).first;
    await tester.tap(cardTap);
    await settle(tester);

    expect(find.text('DISPUTE DETAILS'), findsOneWidget);
    // Using default find() (skipOffstage: true) — the exact same check that
    // previously failed and reported "blank" before this fix.
    expect(find.textContaining('Om Sai Enterprises'), findsWidgets, reason: 'Customer name must genuinely render (not just exist offstage)');
    expect(find.textContaining('₹25,000'), findsWidgets, reason: 'Dispute amount must genuinely render');
    expect(find.textContaining('Goods received damaged'), findsWidgets, reason: 'Dispute reason must genuinely render');
    expect(find.text('DISPUTE SUMMARY'), findsOneWidget);
    expect(find.text('RESOLUTION PLAN'), findsOneWidget);
    expect(find.text('TIMELINE'), findsOneWidget);
    print('✓ Dispute Details screen genuinely shows its full content (customer, amount, reason, sections)');

    await tester.tap(find.text('Approve & Assign'));
    await settle(tester);
    expect(find.text('APPROVING DISPUTE'), findsOneWidget, reason: 'Approve & Assign form must genuinely render its content');
    expect(find.textContaining('Om Sai Enterprises'), findsWidgets);
    expect(find.text('ASSIGNMENT DETAILS'), findsOneWidget);
    expect(find.text('OPERATIONAL EFFECT'), findsOneWidget);
    print('✓ Approve & Assign screen genuinely shows its full content');

    print('✓ COMPLETE: both dispute screens genuinely render their content, not just their action buttons.');
  });
}
