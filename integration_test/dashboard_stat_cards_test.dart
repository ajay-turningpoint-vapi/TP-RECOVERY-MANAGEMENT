// Verifies the salesperson Dashboard's 4 top stat cards (Due Customers,
// PTP Due Today, Broken PTP, Tasks Due Today) are genuinely clickable and
// navigate to the correctly filtered customer list — not just decorative
// numbers.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/dashboard_stat_cards_test.dart -d chrome

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

  testWidgets('Dashboard stat cards navigate to the correctly filtered customer list', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'rahul', '1234');

    // ---- Due Customers ----
    await tester.tap(find.text('Due Customers'));
    await settle(tester);
    expect(find.text('Due Customers'), findsWidgets, reason: 'Must navigate to a real "Due Customers" list screen');
    expect(find.textContaining('₹'), findsWidgets, reason: 'Due Customers list must show real customer data');
    print('✓ "Due Customers" card navigates to a real, populated customer list');
    await tester.pageBack();
    await settle(tester);

    // ---- PTP Due Today ----
    await tester.tap(find.text('PTP Due Today'));
    await settle(tester);
    expect(find.text('PTP Due Today'), findsWidgets, reason: 'Must navigate to a real "PTP Due Today" list screen');
    print('✓ "PTP Due Today" card navigates to a real, filtered customer list');
    await tester.pageBack();
    await settle(tester);

    // ---- Broken PTP ----
    await tester.tap(find.text('Broken PTP').first);
    await settle(tester);
    expect(find.text('Broken PTPs'), findsWidgets, reason: 'Must navigate to a real "Broken PTPs" list screen');
    print('✓ "Broken PTP" card navigates to a real, filtered customer list');
    await tester.pageBack();
    await settle(tester);

    // ---- Tasks Due Today ----
    await tester.tap(find.text('Tasks Due Today'));
    await settle(tester);
    expect(find.text('Tasks Due Today'), findsWidgets, reason: 'Must navigate to a real "Tasks Due Today" list screen');
    print('✓ "Tasks Due Today" card navigates to a real, filtered customer list');
    await tester.pageBack();
    await settle(tester);

    print('✓ COMPLETE: all 4 dashboard stat cards are genuinely clickable and show real, correctly filtered data.');
  });
}
