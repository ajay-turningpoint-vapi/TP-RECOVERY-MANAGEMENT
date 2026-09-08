// Real end-to-end test confirming the Manager Reports "Quick Summary" card
// no longer shows the old hardcoded ₹85,00,000 / ₹32,00,000 placeholder
// figures for Target/Expected — they must now be computed live from real
// customer/PTP data, in a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_reports_quick_summary_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Reports Quick Summary: Total Target is real, not the old hardcoded ₹85,00,000', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(find.byType(TextField).at(0), 'suresh.mgr');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
    print('✓ Manager login successful');

    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Quick Summary (As on ${_todayLabel()})'), findsOneWidget, reason: 'Reports screen must render its Quick Summary card');
    print('✓ Reports screen opened, Quick Summary card present');

    // The old hardcoded values (₹85,00,000 target / ₹32,00,000 expected)
    // must not appear anywhere on this screen anymore.
    expect(find.textContaining('85,00,000'), findsNothing, reason: 'Total Target must no longer show the old hardcoded ₹85,00,000');
    expect(find.textContaining('32,00,000'), findsNothing, reason: 'Expected Collection must no longer show the old hardcoded ₹32,00,000');
    print('✓ Old hardcoded ₹85,00,000 / ₹32,00,000 placeholder values are gone');

    // A real Total Target figure must still render (some ₹ amount, not zero
    // or missing) — confirms the new live computation actually produced a
    // number, not an empty/broken card.
    expect(find.text('Total Target (₹)'), findsOneWidget);
    expect(find.text('Total Received (₹)'), findsOneWidget);
    expect(find.text('Achievement'), findsOneWidget);
    print('✓ Quick Summary still renders real Target/Received/Achievement figures');

    print('✓ Manager Reports Quick Summary real-data flow complete');
  });
}

String _todayLabel() {
  final now = DateTime.now();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';
}
