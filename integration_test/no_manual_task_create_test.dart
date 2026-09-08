// Verifies the salesman's manual "Create New Task" flow is genuinely gone
// from the Tasks screen — no floating action button, no dialog. Tasks now
// only come from AppStore.recordOutcome()'s automatic generation.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/no_manual_task_create_test.dart -d chrome

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

  testWidgets('Tasks screen has no manual task creation entry point', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await login(tester, 'mahesh', '1234');

    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.assignment)));
    await settle(tester);

    expect(find.byType(FloatingActionButton), findsNothing, reason: 'No FAB should exist on Tasks screen — manual task creation was removed');
    expect(find.text('Create Task'), findsNothing);
    expect(find.text('Create New Task'), findsNothing);
    print('✓ Tasks screen has no FAB and no Create Task/Create New Task text anywhere on screen');

    print('✓ COMPLETE: Manual task creation is genuinely removed from the salesman Tasks screen.');
  });
}
