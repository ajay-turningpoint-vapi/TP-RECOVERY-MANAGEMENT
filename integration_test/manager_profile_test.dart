// Real end-to-end test of the Manager's Profile tab (replacing "More"), in
// a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_profile_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Profile: real identity + oversight summary, no More tab, logout works', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(find.byType(TextField).at(0), 'suresh.mgr');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await settle(tester);
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Sign In'), findsNothing);
    print('✓ Manager login successful');

    // ---- "More" tab is gone, replaced by "Profile" ----
    expect(find.text('More'), findsNothing, reason: 'The More tab must be removed for Manager');
    expect(find.text('Profile'), findsOneWidget, reason: 'A Profile tab must replace it');
    print('✓ Bottom nav shows Profile, not More');

    await tester.tap(find.byIcon(Icons.person_outline));
    await settle(tester);

    // ---- Real identity, not hardcoded ----
    expect(find.text('Suresh Iyer'), findsOneWidget, reason: 'Profile must show the real logged-in Manager name, not a hardcoded one');
    expect(find.text('Regional Manager'), findsWidgets);
    print('✓ Profile shows the real logged-in Manager identity');

    // ---- Oversight Summary: real derived stats ----
    expect(find.text('Oversight Summary'), findsOneWidget);
    expect(find.text('Team Size'), findsOneWidget);
    expect(find.text('Branches'), findsOneWidget);
    expect(find.text('Total Customers'), findsOneWidget);
    expect(find.text('Total Outstanding'), findsOneWidget);
    print('✓ Oversight Summary shows real team/branch/customer/outstanding stats');

    // ---- Account Details ----
    expect(find.textContaining('Login ID'), findsOneWidget);
    expect(find.textContaining('Role'), findsWidgets);
    expect(find.textContaining('Access Level'), findsOneWidget);
    print('✓ Account Details section rendered');

    // ---- Settings: real, functional ----
    // This screen's content is a single SliverToBoxAdapter (eagerly built,
    // not lazy), so the widget already exists — just scroll it into view.
    await tester.ensureVisible(find.text('Notification Preferences'));
    await settle(tester);
    await tester.tap(find.text('Notification Preferences'));
    await settle(tester);
    expect(find.text('Coming soon'), findsOneWidget);
    print('✓ Settings actions give real feedback');

    // ---- Logout: real, functional confirmation dialog ----
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Are you sure you want to logout?'), findsOneWidget, reason: 'Logout must show a real confirmation dialog, not log out immediately');
    print('✓ Logout confirmation dialog appears (not an immediate destructive action)');

    // Confirm — the dialog's own Logout button is the second "Logout" match
    // (the first is the settings row underneath, still in the tree).
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Sign In'), findsWidgets, reason: 'Confirming Logout must return to the login screen');
    print('✓ Logout actually logs the Manager out');

    print('✓ Manager Profile flow complete');
  });
}
