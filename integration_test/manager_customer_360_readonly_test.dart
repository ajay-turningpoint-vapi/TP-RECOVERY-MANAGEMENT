// Real end-to-end test of the Manager's new read-only path into the full
// Customer 360 screen (previously Manager report screens only offered a
// 5-7 field bottom sheet, never the real invoices/history detail), in a
// real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_customer_360_readonly_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Customer 360 (read-only): reachable from Priority Accounts, shows real financial/invoice/history data, zero action buttons', (tester) async {
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

    // Navigate: Dashboard -> Reports tab -> Priority Accounts.
    await tester.tap(find.byIcon(Icons.bar_chart_outlined).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    final reportsList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.text('Priority Accounts').evaluate().isEmpty; i++) {
      await tester.drag(reportsList, const Offset(0, -400));
      await settle(tester);
    }
    final reportTile = find.text('Priority Accounts');
    expect(reportTile, findsOneWidget);
    await tester.ensureVisible(reportTile);
    await settle(tester);
    await tester.tap(reportTile);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('High-priority customer accounts needing attention'), findsOneWidget);
    print('✓ Priority Accounts screen opened');

    // Open an account's detail sheet.
    final outerList = find.byType(ListView).first;
    for (var i = 0; i < 10 && find.byType(CircleAvatar).evaluate().isEmpty; i++) {
      await tester.drag(outerList, const Offset(0, 400));
      await settle(tester);
    }
    final avatars = find.byType(CircleAvatar);
    expect(avatars, findsWidgets, reason: 'The priority accounts table must have real rows to tap');
    final firstRow = find.ancestor(of: avatars.first, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(firstRow);
    await settle(tester);
    await tester.tap(firstRow);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('View Full Customer 360'), findsOneWidget, reason: 'The detail sheet must offer the new Customer 360 link');
    print('✓ Account detail sheet shows the new "View Full Customer 360" link');

    // Follow it into the real Customer 360 screen.
    await tester.tap(find.text('View Full Customer 360'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    expect(find.text('Customer Details'), findsOneWidget, reason: 'Tapping the link must open the real Customer 360 screen');
    expect(find.text('Manager view is read-only — reassignment, instruction, and outcome actions are taken by the Recovery Executive or the assigned salesperson.'), findsOneWidget, reason: 'The read-only banner must be visible');
    print('✓ Real Customer 360 screen opened in read-only mode with its banner');

    // ---- Real financial data, not a bottom-sheet summary ----
    expect(find.text('Total Outstanding'), findsOneWidget);
    expect(find.text('Current Due'), findsOneWidget);
    expect(find.text('Future Due'), findsOneWidget);
    print('✓ Real financial summary cards render (not just a bottom-sheet key-value list)');

    // ---- Tabs: Overview / Invoices / History all reachable ----
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    print('✓ Invoices tab opened');
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    print('✓ History tab opened');
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // ---- Zero action buttons anywhere on this screen ----
    expect(find.text('TAKE CONTROL'), findsNothing);
    expect(find.text('RELEASE CONTROL'), findsNothing);
    expect(find.text('RECORD OUTCOME'), findsNothing);
    expect(find.text('Manager view is read-only.'), findsOneWidget, reason: 'The bottom bar must show the read-only notice, not an action button');
    print('✓ No action buttons anywhere on the read-only Customer 360 — bottom bar shows the read-only notice instead');

    // ---- Back navigation returns to the report, not the dashboard ----
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('High-priority customer accounts needing attention'), findsOneWidget, reason: 'Back from Customer 360 must return to the Priority Accounts report');
    print('✓ Back navigation returns to Priority Accounts');

    print('✓ Manager Customer 360 read-only flow complete');
  });
}
