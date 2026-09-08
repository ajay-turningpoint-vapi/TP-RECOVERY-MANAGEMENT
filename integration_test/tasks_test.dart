// Real end-to-end test of the Salesman My Tasks feature, in a real Chrome
// browser via chromedriver. (RE Tasks is covered separately in
// re_tasks_e2e_test.dart — kept in its own file for session-length
// reliability.) Manual task creation was deliberately removed — tasks now
// only come from AppStore.recordOutcome()'s automatic generation — and its
// absence is verified separately in no_manual_task_create_test.dart, so
// this file only covers filters/search/Edit Task. Run with:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/tasks_test.dart -d chrome

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

  testWidgets('Salesman My Tasks: filters, search, Edit Task -> RE approval request', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await login(tester, 'rahul', '1234');
    expect(find.text('Sign In'), findsNothing);
    print('✓ Salesman login successful');

    await tester.tap(find.byIcon(Icons.assignment).last);
    await settle(tester);
    expect(find.text('My Tasks'), findsOneWidget, reason: 'Tasks tab must open My Tasks');
    print('✓ My Tasks screen opened');

    // ---- Filter tabs ----
    for (final tab in ['Overdue', 'Today', 'Upcoming', 'All']) {
      await tester.tap(find.text(tab));
      await settle(tester);
      print('✓ Filter tab "$tab" tapped and rendered without error');
    }

    // ---- Search box: real filtering ----
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'zzz_no_such_task_zzz');
    await settle(tester);
    expect(find.text('No tasks found.'), findsOneWidget, reason: 'Search must actually filter the list — a nonsense query must show the empty state');
    print('✓ Search box genuinely filters the task list (nonsense query -> empty state)');
    await tester.enterText(searchField, '');
    await settle(tester);

    await tester.tap(find.text('All'));
    await settle(tester);

    // ---- Edit Task -> routes to RE approval (not a self-approve loop) ----
    // Uses one of rahul's real seeded tasks (T1/T2) rather than a newly
    // created one — manual task creation was deliberately removed from
    // this screen (see no_manual_task_create_test.dart).
    final editIcon = find.widgetWithIcon(IconButton, Icons.edit_note);
    expect(editIcon, findsWidgets, reason: 'An owned, non-completed task must offer an Edit action');
    await tester.ensureVisible(editIcon.first);
    await settle(tester);
    await tester.tap(editIcon.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Edit Task Details'), findsOneWidget, reason: 'Edit icon must open the edit dialog');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Approval Required'), findsOneWidget, reason: 'Editing a task must require RE approval, not apply silently');
    await tester.tap(find.text('Send Request'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Edit request sent'), findsOneWidget, reason: 'Sending the edit request must show a real confirmation snackbar');
    print('✓ Edit Task: real approval-required flow confirmed — edit request sent to RE, not applied directly');

    await tester.tap(find.text('All'));
    await settle(tester);
    expect(find.text('Edit Awaiting Executive Approval'), findsOneWidget, reason: 'The task card must show the pending-approval banner');
    expect(find.textContaining('Approve (Dev)'), findsNothing, reason: 'A salesman must never be able to self-approve their own edit request — this control must not exist on their own screen');
    print('✓ Verified: pending-approval banner shown, and — critically — no self-approve control exists on the salesman\'s own screen');

    print('✓ Salesman My Tasks flow complete');
  });
}
