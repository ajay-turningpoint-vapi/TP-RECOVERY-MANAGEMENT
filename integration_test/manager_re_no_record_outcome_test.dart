// Verifies Management can never see "RECORD OUTCOME" on Customer 360,
// regardless of which screen navigated there. Previously the read-only
// guard depended entirely on each caller remembering to pass
// `readOnly: true` — most of the ~30 real navigation sites didn't, so a
// Manager reaching Customer 360 through, e.g., the Customers tab
// (CompanyRecoveryQueueScreen, shared with RE) would see a live
// "RECORD OUTCOME" button. Fixed by deriving read-only from the real role
// inside Customer 360 itself.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_re_no_record_outcome_test.dart -d chrome

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

  testWidgets('Manager reaching Customer 360 via the Customers tab (no readOnly passed) still sees no RECORD OUTCOME', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'suresh.mgr', '1234');
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.people_outline)));
    await settle(tester);

    final abcFinder = find.text('ABC Traders').first;
    for (var i = 0; i < 12 && abcFinder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.tap(abcFinder);
    await settle(tester);

    expect(find.text('RECORD OUTCOME'), findsNothing, reason: 'Management must never be able to record an outcome, from any entry point');
    expect(find.textContaining('Manager view is read-only'), findsWidgets, reason: 'The real read-only banner must appear even though this screen never passed readOnly: true explicitly');
    print('✓ Manager reaching Customer 360 via the Customers tab (CompanyRecoveryQueueScreen, which never passes readOnly) genuinely sees no RECORD OUTCOME button — the real read-only banner shows instead');

    print('✓ COMPLETE: Read-only is now derived from the real Management role, not dependent on every caller remembering a flag.');
  });
}
