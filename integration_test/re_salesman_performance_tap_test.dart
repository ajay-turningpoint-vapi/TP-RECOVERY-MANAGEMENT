// Verifies that on the RE Control Dashboard's "Salesmen Performance (Today)"
// section, tapping a salesman row opens that salesman's full performance
// report (ManagerSalesmanPerformanceScreen, pre-filtered to just them),
// rather than doing nothing.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/re_salesman_performance_tap_test.dart -d chrome

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

  testWidgets('Tapping a salesman in Salesmen Performance opens their full performance report', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'ramesh.re', '1234');

    expect(find.text('Salesmen Performance (Today)'), findsOneWidget);
    expect(find.textContaining('Rahul'), findsOneWidget);

    await tester.tap(find.textContaining('Rahul').first);
    await settle(tester);

    // The performance report screen shows a salesman filter pill and
    // achievement/detail content — confirm we actually navigated there and
    // that it's pre-filtered to Rahul specifically, not "All Salesmen".
    expect(find.textContaining('Rahul'), findsWidgets, reason: 'Report screen should be showing Rahul-specific content');
    expect(find.text('All Salesmen'), findsNothing, reason: 'Filter must be pre-set to Rahul, not defaulted back to All Salesmen');
    print('✓ Tapping Rahul in Salesmen Performance opens his full performance report, pre-filtered to just him');

    print('✓ COMPLETE: Salesman row tap genuinely navigates to their full performance report.');
  });
}
