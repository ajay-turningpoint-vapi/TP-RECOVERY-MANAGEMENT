// Verifies that when RE approves (or rejects) a salesperson's task-edit
// (extension) request, a real audit entry now lands on the CUSTOMER's own
// history — not just the task's fields — so any role opening that
// customer's Customer 360 History tab sees what RE did in one glance.
// Previously approveTaskEdit()/rejectTaskEdit() silently changed the task
// but wrote nothing to the customer's auditHistory — a real gap, now fixed.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/re_task_edit_audit_trail_test.dart -d chrome

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

  Future<void> scrollUntilVisible(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
  }

  // ReTasksScreen has TWO Scrollables — a horizontal stat-card filter row
  // (built first, so it's Scrollable.first) and the actual vertical task
  // ListView (Scrollable.last). Dragging .first there does nothing useful.
  Future<void> scrollVerticalListUntilVisible(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
  }

  // ReTasksScreen paginates behind a "Load More" button (starts at 6 visible
  // items) rather than lazily rendering everything. Tapping "Load More"
  // raises the item cap but the newly-unlocked item can still be off-screen
  // (below the current scroll position) — and once every item is unlocked,
  // "Load More" itself disappears, so a loop that only chases "Load More"
  // stops too early. Unlock pagination first, then do a final plain scroll
  // pass for the real target.
  Future<void> loadMoreUntilVisible(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 10 && finder.evaluate().isEmpty; i++) {
      final loadMore = find.text('Load More  ⌄');
      await scrollVerticalListUntilVisible(tester, loadMore);
      if (loadMore.evaluate().isEmpty) break;
      await tester.tap(loadMore.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
    await scrollVerticalListUntilVisible(tester, finder);
  }

  Future<void> logout(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.person));
    await settle(tester);
    for (var i = 0; i < 10 && find.text('Logout').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').first);
    await settle(tester);
    await tester.tap(find.text('Logout').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  testWidgets('RE approving a task-edit request leaves a real trail on the customer History tab', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ================= Rahul requests an extension on his ABC Traders task =================
    await login(tester, 'rahul', '1234');
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.assignment)));
    await settle(tester);
    // T1's task card shows its reason text, not the customer name directly.
    final rahulTaskFinder = find.text('Customer not answering calls — physical visit required');
    await scrollUntilVisible(tester, rahulTaskFinder);
    await tester.tap(rahulTaskFinder);
    await settle(tester);

    await tester.tap(find.text('Extend'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Customer asked for 2 more days to arrange funds');
    await settle(tester);
    await tester.tap(find.text('Submit'));
    await settle(tester);
    print('✓ Rahul requested a task extension on ABC Traders');

    // Submitting the extension dialog only closes the dialog — still on
    // the task detail screen. A tap on the AppBar's back button can land on
    // a still-settling route-transition overlay right after a dialog closes
    // (Flutter only warns, doesn't fail, then silently misses) — pop the
    // route directly via the Navigator instead, which is coordinate-free
    // and deterministic.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await logout(tester);

    // ================= RE approves the extension =================
    await login(tester, 'ramesh.re', '1234');
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.assignment_outlined)));
    await settle(tester);
    final extensionFinder = find.text('Task Extension Request');
    await loadMoreUntilVisible(tester, extensionFinder);
    expect(extensionFinder, findsOneWidget);
    await tester.tap(extensionFinder);
    await settle(tester);

    expect(find.text('Approve Extension'), findsOneWidget);
    await tester.tap(find.text('Approve Extension'));
    await settle(tester);
    print('✓ RE approved the task extension request');

    // ================= Confirm it landed on ABC Traders' customer history =================
    await tester.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.byIcon(Icons.people_outline)));
    await settle(tester);
    final abcFinder = find.text('ABC Traders').first;
    await scrollUntilVisible(tester, abcFinder);
    await tester.tap(abcFinder);
    await settle(tester);
    await tester.tap(find.text('History'));
    await settle(tester);

    // History is a lazily-built list — scroll until the real audit entry is
    // actually built and visible before asserting on its content.
    await scrollUntilVisible(tester, find.textContaining('approved'));
    expect(find.textContaining('approved'), findsWidgets, reason: 'The customer History tab must show RE approving the task edit, in one glance');
    await scrollUntilVisible(tester, find.textContaining('Customer asked for 2 more days'));
    expect(find.textContaining('Customer asked for 2 more days'), findsWidgets, reason: 'The salesperson\'s stated reason should be visible in the RE\'s audit entry too');
    print('✓ ABC Traders\' History tab genuinely shows the RE\'s task-edit approval — visible to any role viewing this customer');

    print('✓ COMPLETE: RE task-edit actions now leave a real, visible customer-level audit trail.');
  });
}
