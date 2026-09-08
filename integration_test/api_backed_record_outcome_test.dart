// Real end-to-end test of the API-backed vertical slice: pumps the actual
// v3 app in a real Chrome browser via chromedriver, and the app's LoginScreen
// now calls AppStore.loginWithApi -> the real TP-RMS Express server on
// 127.0.0.1:4000 -> real MariaDB. No mocks anywhere in this path.
//
// Requires: `pm2 start ecosystem.config.js` (or `npm run dev` + `npm run
// worker:dev`) running in server/ first.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/api_backed_record_outcome_test.dart -d chrome
//
// NOTE: on this Flutter/Chrome combination, `flutter drive` on web has been
// observed running the testWidgets body twice concurrently in the same
// tab (confirmed via server request logs: two independent, well-formed
// login+record-outcome sequences, ~3s apart, each fully valid on its own —
// not a double-tap or a retry from the app itself). That's a driver/web
// harness quirk, not an app bug — the same flow was also verified via a
// clean, single-request run in test/api_client_integration_test.dart
// (VM-based, not a browser). History-tab assertions below use findsWidgets
// rather than findsOneWidget to tolerate the resulting duplicate render.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
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

  Future<void> pickFirstDateThenTime(WidgetTester tester, {required String dateLabel, required String timeLabel}) async {
    await tester.tap(find.text(dateLabel));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.tap(find.text(timeLabel));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  testWidgets('Salesman: real API login, real customer list, real Record Outcome round-trip through MariaDB', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Sign In'), findsWidgets, reason: 'Login screen must render');
    await login(tester, 'rahul', '1234');
    expect(find.text('Sign In'), findsNothing, reason: 'Must have navigated away from login after valid credentials');

    final store = Provider.of<AppStore>(tester.element(find.byType(MaterialApp).first), listen: false);
    expect(store.isApiBacked, isTrue, reason: 'This session must be backed by the real API, not BusySimulator demo data');
    expect(store.customers, isNotEmpty, reason: 'Real customers must have been fetched from the live server');
    print('✓ Real API login successful — isApiBacked=true, ${store.customers.length} real customers loaded from MariaDB');

    await tester.tap(find.byIcon(Icons.people).last);
    await settle(tester);
    print('✓ Customers tab opened, showing real API-backed data');

    final customerRow = find.byType(InkWell);
    expect(customerRow, findsWidgets, reason: 'Real customer list must render at least one tappable row');
    // Pick a customer that isn't already locked (currentRecoveryState !=
    // 'Waiting / Monitoring') so this test is re-runnable without needing
    // to reseed the database every time — recordOutcome disables the
    // button once an outcome has already been recorded.
    final targetIndex = store.myCustomers.indexWhere((c) => c.currentRecoveryState != 'Waiting / Monitoring');
    expect(targetIndex, greaterThanOrEqualTo(0), reason: 'Every seeded customer is locked — reseed the dev database (npm run seed) before re-running this test');
    final target = store.myCustomers[targetIndex];
    await tester.tap(customerRow.at(targetIndex));
    await settle(tester);
    expect(find.text('Customer Details'), findsOneWidget, reason: 'Tapping a real customer must open Customer 360');
    print('✓ Opened real Customer 360 for ${target.name} (${target.id})');

    await tester.tap(find.text('RECORD OUTCOME'));
    await settle(tester);
    await tester.tap(find.text('Will Confirm'));
    await settle(tester);
    await pickFirstDateThenTime(tester, dateLabel: 'Select Follow-up Date', timeLabel: 'Select Follow-up Time');
    await tester.tap(find.text('SAVE OUTCOME'));
    // The real network round-trip to the API needs more than the usual
    // settle window — wait for the actual server response, not a fixed
    // animation duration.
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining('Outcome recorded'), findsWidgets, reason: 'A real API record-outcome call must show the confirmation snackbar on success, not silently fail');
    print('✓ Will Confirm outcome submitted via the real API — server responded, UI confirmed');

    await tester.tap(find.text('History'));
    await settle(tester);
    expect(find.textContaining('Follow-Up Scheduled'), findsWidgets, reason: 'History tab must reflect the real audit_events row the server just wrote to MariaDB');
    expect(find.textContaining('Rahul Sharma'), findsWidgets, reason: 'History must attribute the entry to the real logged-in user from the JWT, not a hardcoded name');
    print('✓ History tab shows the real audit entry written by the server, correctly attributed');

    // Confirm the customer's state actually round-tripped through the API
    // and MariaDB (not just held in the client's in-memory copy after a
    // synchronous local mutation, which is how the old BusySimulator path
    // worked).
    final refreshed = store.customers.firstWhere((c) => c.id == target.id);
    expect(refreshed.currentRecoveryState, 'Waiting / Monitoring', reason: 'Customer state must reflect the server\'s real recordOutcome response');
    print('✓ Confirmed real round-trip: customer state came back from the server, not a local-only mutation');
  });
}
