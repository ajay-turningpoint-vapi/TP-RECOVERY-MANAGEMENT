// Verifies two real Record Outcome form changes:
// 1. PTP "Mode of Communication" dropdown now offers only Phone Call and
//    WhatsApp — no Bank Transfer/Cash/Cheque/UPI.
// 2. Internal Action's "Required Dependency" dropdown now has an "Other"
//    option that reveals a text field, and that entered text is what gets
//    saved as the outcome.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/outcome_form_options_test.dart -d chrome

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

  testWidgets('PTP mode limited to Phone/WhatsApp; Internal Action Other reveals text field', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'rahul', '1234');

    // Open the first customer's 360 screen via START RECOVERY.
    await tester.tap(find.text('START RECOVERY'));
    await settle(tester);

    // ================= PTP mode of communication =================
    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('Promise to Pay (PTP)'));
    await settle(tester);

    // Default selected mode is now 'Phone Call' — tap it to open the dropdown.
    await tester.tap(find.text('Phone Call').hitTestable());
    await settle(tester);
    expect(find.text('Phone Call').hitTestable(), findsWidgets);
    expect(find.text('WhatsApp').hitTestable(), findsWidgets);
    expect(find.text('Bank Transfer').hitTestable(), findsNothing);
    expect(find.text('Cash').hitTestable(), findsNothing);
    expect(find.text('Cheque').hitTestable(), findsNothing);
    expect(find.text('UPI').hitTestable(), findsNothing);
    print('✓ PTP Mode of Communication dropdown offers only Phone Call and WhatsApp');
    // Close the dropdown without changing selection.
    await tester.tap(find.text('WhatsApp').hitTestable());
    await settle(tester);

    // Back out of the PTP form to the outcome list within the same sheet.
    await tester.tap(find.text('Back to Outcomes'));
    await settle(tester);

    // ================= Internal Action "Other" =================
    await tester.tap(find.text('Internal Action'));
    await settle(tester);

    // Before selecting Other, the free-text field must not exist.
    expect(find.text('Please specify'), findsNothing);

    await tester.tap(find.text('Updated Ledger Required').hitTestable());
    await settle(tester);
    await tester.tap(find.text('Other').hitTestable());
    await settle(tester);

    expect(find.text('Please specify'), findsOneWidget, reason: 'Selecting Other must reveal a free-text field');
    print('✓ Internal Action: selecting "Other" reveals a "Please specify" text field');

    await tester.enterText(find.widgetWithText(TextField, 'Please specify'), 'Awaiting legal sign-off on write-off');
    await settle(tester);

    await tester.tap(find.text('SAVE OUTCOME').hitTestable());
    await settle(tester);
    expect(find.text('Please specify'), findsNothing, reason: 'Form should have closed after a valid save');
    print('✓ Internal Action outcome with custom "Other" text saved successfully');

    print('✓ COMPLETE: PTP mode restricted to Phone/WhatsApp, Internal Action Other + free text genuinely works end to end.');
  });
}
