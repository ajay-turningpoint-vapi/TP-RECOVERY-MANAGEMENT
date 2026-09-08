// Focused E2E test: the three evidence-gated Record Outcome options
// (No Answer, Payment Already Made, Dispute Raised) — verifies each form
// renders and blocks an empty submission with a real validation error.
// (Evidence capture itself opens a native browser file dialog that
// WidgetTester cannot drive.) Kept separate from Profile/Logout — see
// salesman_profile_logout_test.dart — for session-length reliability.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/salesman_evidence_validation_test.dart -d chrome

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

  Future<void> openFirstCustomer(WidgetTester tester) async {
    final customerRow = find.byType(InkWell);
    expect(customerRow, findsWidgets, reason: 'Customer list must render at least one tappable row');
    await tester.tap(customerRow.first);
    await settle(tester);
    expect(find.text('Customer Details'), findsOneWidget, reason: 'Tapping a customer must open Customer 360');
  }

  testWidgets('Salesman: No Answer, Payment Already Made, Dispute Raised — validation blocks empty submission', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'rahul', '1234');
    expect(find.text('Sign In'), findsNothing);
    print('✓ Salesman login successful, landed on Dashboard');

    await tester.tap(find.byIcon(Icons.people).last);
    await settle(tester);
    print('✓ Customers tab opened');

    for (final spec in [
      ('No Answer', 'No Answer', 'Screenshot evidence is required'),
      ('Payment Already Made', 'Payment Already Made', 'Evidence screenshot is required'),
      ('Dispute Raised', 'Dispute / Issue', 'Required'),
    ]) {
      await openFirstCustomer(tester);
      await tester.tap(find.text('RECORD OUTCOME'));
      await settle(tester);
      await tester.tap(find.text(spec.$1));
      await settle(tester);
      expect(find.text(spec.$2), findsWidgets, reason: '${spec.$1} form must render with its real title');
      await tester.tap(find.text('SAVE OUTCOME'));
      await settle(tester);
      expect(find.textContaining(spec.$3), findsWidgets, reason: '${spec.$1} must block an empty submission with a real validation error');
      print('✓ ${spec.$1}: form renders correctly, empty submission genuinely blocked by validation (evidence capture requires a native browser dialog outside WidgetTester\'s reach — not exercised)');
      // Dismiss the outcome bottom sheet reliably by dragging it down —
      // a coordinate tapAt() can miss the barrier depending on form height,
      // leaving the sheet open and desyncing the next loop iteration's
      // navigation (this was intermittently breaking openFirstCustomer()
      // on the following iteration).
      await tester.drag(find.byType(BottomSheet), const Offset(0, 600));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pageBack();
      await settle(tester);
    }

    print('✓ Evidence-gated outcomes validation complete');
  });
}
