// Verifies the salesman's Task Details screen action row now shows only
// "Extend" — "Reassign" and "Complete" were removed on request.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/task_extend_only_test.dart -d chrome

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

  testWidgets('Salesman Task Details shows only Extend, not Reassign or Complete', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'rahul', '1234');

    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.assignment)));
    await settle(tester);
    await tester.tap(find.text('Customer not answering calls — physical visit required'));
    await settle(tester);

    expect(find.text('Extend'), findsOneWidget, reason: 'Extend must remain the one available action');
    expect(find.text('Reassign'), findsNothing, reason: 'Reassign must be removed from the salesman task action row');
    expect(find.text('Complete'), findsNothing, reason: 'Complete must be removed from the salesman task action row');
    print('✓ Salesman Task Details action row shows only Extend — Reassign and Complete are genuinely gone');

    print('✓ COMPLETE: Salesman task actions correctly reduced to Extend only.');
  });
}
