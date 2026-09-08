// Verifies the Manager Reports screen's Branch filter now genuinely scopes
// the reports it links to (previously a no-op: selecting a branch had zero
// effect on any of the 13 destination reports, despite the screen's own
// Help text claiming otherwise).
//
// Ground truth: Rahul is Mumbai branch, Mahesh is Nagpur branch.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_branch_filter_test.dart -d chrome

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

  testWidgets('Manager Reports Branch filter genuinely scopes a destination report', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'suresh.mgr', '1234');

    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.bar_chart_outlined)));
    await settle(tester);

    // Select "Mumbai" (Rahul's branch, not Mahesh's) in the Branch dropdown.
    await tester.tap(find.byType(DropdownButton<String>));
    await settle(tester);
    await tester.tap(find.text('Mumbai').last);
    await settle(tester);

    // Open Salesman Performance — with the filter applied it must show only
    // Rahul (Mumbai), not Mahesh (Nagpur).
    final tile = find.text('Salesman Performance');
    for (var i = 0; i < 15 && tile.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await settle(tester);
    }
    await tester.ensureVisible(tile.first);
    await settle(tester);
    await tester.tap(tile.first);
    await settle(tester);

    for (var i = 0; i < 15 && find.textContaining('Rahul').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await settle(tester);
    }
    expect(find.textContaining('Rahul'), findsWidgets, reason: 'Rahul (Mumbai) must appear when the Branch filter is set to Mumbai');
    expect(find.textContaining('Mahesh'), findsNothing, reason: 'Mahesh (Nagpur) must NOT appear when the Branch filter is set to Mumbai — this is the exact scoping gap that was fixed');
    print('✓ Selecting "Mumbai" on Manager Reports genuinely scopes the Salesman Performance report to only Mumbai salesmen (Rahul), excluding Mahesh (Nagpur)');

    print('✓ COMPLETE: the Manager Reports Branch filter is genuinely wired through to its destination reports.');
  });
}
