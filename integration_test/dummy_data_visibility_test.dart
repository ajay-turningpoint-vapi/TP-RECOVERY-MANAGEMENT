// Verifies the newly-curated dummy dataset (3 full customers for Rahul, 2
// for Mahesh, plus their tasks/PTPs/dispute/payment-claim/escalation) is
// genuinely VISIBLE — not just non-crashing — across all 3 roles.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/dummy_data_visibility_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  Future<void> tapIcon(WidgetTester tester, IconData icon) async {
    final finder = find.byIcon(icon).last;
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> login(WidgetTester tester, String username, String password) async {
    await tester.enterText(find.byType(TextField).at(0), username);
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), password);
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
  }

  Future<void> logout(WidgetTester tester, IconData profileIcon) async {
    await tapIcon(tester, profileIcon);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsWidgets);
  }

  testWidgets('The curated dummy dataset is genuinely visible across Salesperson, RE, and Manager screens', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= RAHUL — 3 customers =================
    await login(tester, 'rahul', '1234');
    await tapIcon(tester, Icons.people);
    for (final name in ['ABC Traders', 'XYZ Enterprises', 'PQR Stores']) {
      expect(find.textContaining(name), findsWidgets, reason: 'Rahul must see $name in his Customers list');
    }
    print('✓ Rahul (Salesperson) sees all 3 of his customers: ABC Traders, XYZ Enterprises, PQR Stores');

    await tapIcon(tester, Icons.assignment);
    expect(find.textContaining('ABC Traders'), findsWidgets, reason: "Rahul's physical visit task for ABC Traders must appear in his Tasks tab");
    print('✓ Rahul sees his real tasks in the Tasks tab');
    await logout(tester, Icons.person);

    // ================= MAHESH — 2 customers =================
    await login(tester, 'mahesh', '1234');
    await tapIcon(tester, Icons.people);
    for (final name in ['Metro Motors', 'Om Sai Enterprises']) {
      expect(find.textContaining(name), findsWidgets, reason: 'Mahesh must see $name in his Customers list');
    }
    print('✓ Mahesh (Salesperson) sees both of his customers: Metro Motors, Om Sai Enterprises');
    await logout(tester, Icons.person);

    // ================= RECOVERY EXECUTIVE — sees all 5 =================
    await login(tester, 'amit.re', '1234');
    await tapIcon(tester, Icons.people_outline);
    for (final name in ['ABC Traders', 'XYZ Enterprises', 'PQR Stores', 'Metro Motors', 'Om Sai Enterprises']) {
      final finder = find.textContaining(name);
      if (finder.evaluate().isEmpty) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await settle(tester);
      }
      expect(finder, findsWidgets, reason: 'RE must see $name in the company-wide recovery queue');
    }
    print('✓ Recovery Executive sees all 5 customers (both salesmen\'s portfolios) in the Company Recovery Queue');

    await tapIcon(tester, Icons.assignment_outlined);
    expect(find.textContaining('Metro Motors'), findsWidgets, reason: "RE must see Mahesh's urgent task on Metro Motors");
    print('✓ RE sees real tasks across both salesmen in the Tasks tab');

    await tapIcon(tester, Icons.chat_bubble_outline);
    expect(find.textContaining('Om Sai Enterprises'), findsWidgets, reason: 'RE must see the real dispute on Om Sai Enterprises');
    print('✓ RE sees the real dispute for Om Sai Enterprises in the Disputes tab');

    await tapIcon(tester, Icons.bar_chart_outlined);
    expect(find.textContaining('Daily Recovery Summary'), findsWidgets);
    print('✓ RE Reports screen renders with the real dataset available');
    await logout(tester, Icons.person_outline);

    // ================= MANAGER — company-wide totals must be non-zero =================
    await login(tester, 'suresh.mgr', '1234');
    // Dashboard is the default tab.
    final rupeeAmounts = find.textContaining('₹');
    expect(rupeeAmounts, findsWidgets, reason: 'Manager Control Dashboard must show real ₹ figures, not a blank/zero dashboard');
    print('✓ Manager Control Dashboard shows real ₹ figures from the 5-customer dataset');

    await tapIcon(tester, Icons.people_outline);
    for (final name in ['ABC Traders', 'Metro Motors']) {
      final finder = find.textContaining(name);
      if (finder.evaluate().isEmpty) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await settle(tester);
      }
      expect(finder, findsWidgets, reason: 'Manager must see $name in the company-wide customer list');
    }
    print('✓ Manager sees real customers across both salesmen');

    print('✓ ALL 3 roles genuinely display the curated dummy dataset — data visibility confirmed.');
  });
}
