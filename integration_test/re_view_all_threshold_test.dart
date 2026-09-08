// Verifies the RE Control Dashboard's "Salesmen Performance (Today)" section
// hides "View All" when there are fewer than 10 salesmen — the real seed
// data has only 2 (Rahul, Mahesh), so it must be genuinely absent.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/re_view_all_threshold_test.dart -d chrome

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

  testWidgets('RE Control Dashboard hides View All when fewer than 10 salesmen', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'ramesh.re', '1234');

    expect(find.text('Salesmen Performance (Today)'), findsOneWidget);
    // Real seed data has exactly 2 salesmen (Rahul, Mahesh) — well under 10.
    expect(find.textContaining('of 2 Salesmen'), findsOneWidget, reason: 'Sanity check: confirms real seed data is under the 10-salesman threshold');

    // "View All ›" also appears, unconditionally, in the separate "Needs
    // Your Attention" section above — that one is untouched by this fix.
    // So after the fix, exactly ONE "View All ›" should exist on screen
    // (Needs Your Attention's), and it must sit ABOVE the Salesmen
    // Performance heading, not below/inside that section.
    final viewAllFinder = find.text('View All  ›');
    expect(viewAllFinder, findsOneWidget, reason: 'Only the unrelated "Needs Your Attention" View All should remain; Salesmen Performance\'s own View All must be gone');
    final viewAllY = tester.getTopLeft(viewAllFinder).dy;
    final performanceHeadingY = tester.getTopLeft(find.text('Salesmen Performance (Today)')).dy;
    expect(viewAllY, lessThan(performanceHeadingY), reason: 'The remaining View All must belong to Needs Your Attention (above), not Salesmen Performance');
    print('✓ RE Control Dashboard genuinely hides "View All" on Salesmen Performance with only 2 real salesmen (Needs Your Attention\'s own unrelated View All is untouched, as expected)');

    print('✓ COMPLETE: View All threshold behavior verified against real seed data.');
  });
}
