// Verifies the "Due Customers" list (and, by the same shared fix, every
// other customer list reachable from the salesperson Dashboard) now shows
// customers in real recovery-priority order — the same order "START
// RECOVERY" uses — instead of arbitrary/seed order.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/due_customers_priority_test.dart -d chrome

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

  /// Reads the on-screen order of a set of customer names by their
  /// vertical position in the Due Customers list.
  double yPositionOf(WidgetTester tester, String name) {
    final finder = find.textContaining(name).first;
    return tester.getTopLeft(finder).dy;
  }

  testWidgets('Due Customers list shows customers in real recovery-priority order', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= Mahesh: escalation beats everything =================
    await login(tester, 'mahesh', '1234');
    await tester.tap(find.ancestor(of: find.text('Due Customers'), matching: find.byType(InkWell)).first);
    await settle(tester);
    expect(find.textContaining('Metro Motors'), findsWidgets);
    expect(find.textContaining('Om Sai Enterprises'), findsWidgets);
    final metroY = yPositionOf(tester, 'Metro Motors');
    final omSaiY = yPositionOf(tester, 'Om Sai Enterprises');
    expect(metroY, lessThan(omSaiY), reason: 'Metro Motors (escalated L2) must render ABOVE Om Sai Enterprises (not escalated) in Due Customers, matching START RECOVERY\'s own priority pick');
    print('✓ Mahesh\'s Due Customers list shows escalated Metro Motors before unescalated Om Sai Enterprises');

    // ================= Rahul: tiebreaker is oldest overdue days =================
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byIcon(Icons.person));
    await settle(tester);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await login(tester, 'rahul', '1234');
    await tester.tap(find.ancestor(of: find.text('Due Customers'), matching: find.byType(InkWell)).first);
    await settle(tester);
    expect(find.textContaining('ABC Traders'), findsWidgets);
    expect(find.textContaining('XYZ Enterprises'), findsWidgets);
    expect(find.textContaining('PQR Stores'), findsWidgets);
    final abcY = yPositionOf(tester, 'ABC Traders');
    final xyzY = yPositionOf(tester, 'XYZ Enterprises');
    final pqrY = yPositionOf(tester, 'PQR Stores');
    expect(abcY, lessThan(xyzY), reason: 'ABC Traders (45 days overdue) must render above XYZ Enterprises (20 days) — none of Rahul\'s customers are escalated, so oldest-overdue-days is the real tiebreaker');
    expect(xyzY, lessThan(pqrY), reason: 'XYZ Enterprises (20 days overdue) must render above PQR Stores (10 days)');
    print('✓ Rahul\'s Due Customers list shows real priority order by oldest overdue days: ABC Traders > XYZ Enterprises > PQR Stores');

    print('✓ COMPLETE: Due Customers genuinely shows real recovery-priority order, matching START RECOVERY.');
  });
}
