// Verifies the salesperson's own Recovery Score (Master Build Book RMS-05)
// is genuinely visible and explainable on their own Profile screen — not
// just on the RE Reports side.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/salesman_profile_score_test.dart -d chrome

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

  testWidgets('Salesperson Profile shows the real, tappable, explainable Recovery Score', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'rahul', '1234');

    await tester.tap(find.byIcon(Icons.person));
    await settle(tester);
    expect(find.text('My Profile'), findsOneWidget);

    expect(find.text('Recovery Score'), findsOneWidget, reason: 'Salesperson Profile must show their own real Recovery Score');
    expect(find.textContaining('%'), findsWidgets);
    print('✓ Salesperson Profile shows the Recovery Score card');

    final scoreCard = find.ancestor(of: find.text('Recovery Score'), matching: find.byType(InkWell)).first;
    await tester.tap(scoreCard);
    await settle(tester);
    expect(find.text('Why this score'), findsOneWidget, reason: 'Tapping the score must drill into the real RMS-05 component breakdown');
    expect(find.textContaining('Collection Performance'), findsWidgets);
    expect(find.textContaining('Weighted Recovery Score'), findsWidgets);
    print('✓ Tapping the score shows the real RMS-05 component breakdown');

    print('✓ COMPLETE: the salesperson can see and explain their own real Recovery Score from their own Profile screen.');
  });
}
