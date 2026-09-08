// Real end-to-end test: pumps the actual v3 app, taps real rendered
// widgets in a real Chrome browser via chromedriver. Covers Tasks tab
// navigation and the full Profile/Logout flow.
//
// (The four evidence-free outcomes are in salesman_outcomes_test.dart, the
// three evidence-gated outcomes' validation is in
// salesman_evidence_validation_test.dart, and the RE flows are in
// re_dispute_test.dart and re_notes_test.dart — each kept in its own short
// session for reliability.)
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_test.dart -d chrome
//
// (chromedriver must already be running on port 4444.)

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

  testWidgets('Salesman: Tasks tab, Profile, Logout', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Sign In'), findsWidgets, reason: 'Login screen must render');
    await login(tester, 'rahul', '1234');
    expect(find.text('Sign In'), findsNothing, reason: 'Must have navigated away from login after valid credentials');
    print('✓ Salesman login successful, landed on Dashboard');

    await tester.tap(find.byIcon(Icons.assignment).last);
    await settle(tester);
    expect(find.text('My Tasks'), findsOneWidget, reason: 'Tasks tab must show My Tasks screen');
    print('✓ Tasks tab opened');

    await tester.tap(find.byIcon(Icons.person).last);
    await settle(tester);
    expect(find.textContaining('Profile'), findsWidgets, reason: 'Profile tab must render');
    print('✓ Profile tab opened');

    // ---- Logout ----
    final logoutTile = find.text('Logout');
    expect(logoutTile, findsOneWidget);
    await tester.ensureVisible(logoutTile);
    await settle(tester);
    await tester.tap(logoutTile);
    await settle(tester);
    final confirmLogout = find.widgetWithText(ElevatedButton, 'Logout');
    expect(confirmLogout, findsOneWidget, reason: 'Logout must show a confirmation dialog, not log out immediately');
    await tester.tap(confirmLogout);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Sign In'), findsWidgets, reason: 'Must land back on login screen after confirmed logout');
    print('✓ Logout confirmed, returned to login screen');
  });
}
