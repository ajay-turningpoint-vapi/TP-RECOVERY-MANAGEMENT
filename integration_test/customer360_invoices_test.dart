// Verifies the Customer 360 Invoices tab correctly buckets real invoice
// statuses ('Overdue', 'Due Soon', 'Partially Paid'), not just the literal
// 'Due'/'Paid' strings it used to exact-match against.
//
// XYZ Enterprises (C2) has 2 real invoices: one 'Overdue', one 'Due Soon'.
// Before the fix: 'Due Soon' fell through to the Paid/green bucket (exact
// match against 'due' failed), so Paid showed 1 and Due showed 0 — both
// wrong. After the fix: Overdue=1, Due=1 (Due Soon grouped as still-owed),
// Paid=0, and the three sum to the real Total Invoices (2).
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/customer360_invoices_test.dart -d chrome

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

  testWidgets('Customer 360 Invoices tab correctly buckets real invoice statuses', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'rahul', '1234');

    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.people)));
    await settle(tester);

    final customerCard = find.textContaining('XYZ Enterprises');
    for (var i = 0; i < 15 && customerCard.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await settle(tester);
    }
    expect(customerCard, findsWidgets);
    final row = find.ancestor(of: customerCard.first, matching: find.byType(GestureDetector)).first;
    await tester.tap(row);
    await settle(tester);

    await tester.tap(find.text('Invoices'));
    await settle(tester);

    // Each stat is its own Column: [icon, count Text, label Text]. Find the
    // count sibling of each label to read its exact real value.
    String statValue(String label) {
      final col = find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
      final texts = find.descendant(of: col, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
      return texts.first;
    }

    expect(statValue('Total Invoices'), '2', reason: 'Total Invoices must be the real 2 seeded invoices for XYZ Enterprises');
    expect(statValue('Overdue'), '1', reason: 'Overdue must be exactly 1 (the real "Overdue" invoice)');
    expect(statValue('Due'), '1', reason: 'Due must be exactly 1 ("Due Soon" must be bucketed as still-owed, not silently dropped)');
    expect(statValue('Paid'), '0', reason: 'Paid must be exactly 0 — this is the exact bug that was fixed: "Due Soon" used to fall through into the Paid bucket');
    print('✓ Customer 360 Invoices tab for XYZ Enterprises: Total 2, Overdue 1, Due 1, Paid 0 — all real and correctly bucketed');

    print('✓ COMPLETE: Customer 360 Invoices tab genuinely buckets real invoice statuses correctly.');
  });
}
