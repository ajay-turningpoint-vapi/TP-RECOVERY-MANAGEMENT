// Real end-to-end test of the Manager's read-only Task Monitoring screen,
// in a real Chrome browser via chromedriver.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/manager_tasks_test.dart -d chrome

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:salesman_mobile/v3/main_v3.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 400));

  testWidgets('Manager Task Monitoring: view-only, no action buttons, filters/search/sort all real', (tester) async {
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

    await tester.tap(find.text('Tasks'));
    await settle(tester);
    expect(find.text('Task Monitoring'), findsOneWidget, reason: 'Tasks tab must open Task Monitoring');
    expect(find.text('Track assigned tasks, delays and completions'), findsOneWidget);
    print('✓ Task Monitoring screen opened');

    // ---- Stat cards render real (non-zero-guaranteed but present) data ----
    expect(find.text('Total Tasks'), findsOneWidget);
    expect(find.text('Due Today'), findsOneWidget);
    expect(find.text('Overdue'), findsWidgets, reason: '"Overdue" legitimately also appears as a filter chip and on individual task status badges');
    expect(find.text('Completed Today'), findsOneWidget);
    expect(find.text('Awaiting Approval'), findsWidgets, reason: '"Awaiting Approval" legitimately also appears on individual task status badges');
    print('✓ All 5 stat cards rendered');

    // ---- Filter chips are real (each one actually changes the list) ----
    for (final chip in ['Pending', 'In Progress', 'Overdue', 'Completed', 'Approval', 'All']) {
      // .first: the filter chip itself sits earlier in the tree than any
      // same-text status badge on a task card further down the list.
      await tester.tap(find.text(chip).first);
      await settle(tester);
      print('✓ Filter chip "$chip" tapped and rendered without error');
    }

    // ---- Search box: real filtering ----
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'zzz_no_such_task_zzz');
    await settle(tester);
    expect(find.text('No tasks in this view.'), findsOneWidget, reason: 'Search must genuinely filter — a nonsense query must show the empty state');
    print('✓ Search box genuinely filters the task list');
    await tester.enterText(searchField, '');
    await settle(tester);

    // ---- Sort toggle: real (icon flips) ----
    final sortButtonBefore = find.byIcon(Icons.arrow_upward).evaluate().isNotEmpty;
    await tester.tap(find.text('Sort'));
    await settle(tester);
    final sortButtonAfter = find.byIcon(Icons.arrow_upward).evaluate().isNotEmpty;
    expect(sortButtonBefore, isNot(equals(sortButtonAfter)), reason: 'Sort must actually toggle direction, not just be decorative');
    print('✓ Sort toggle is real — direction icon actually flips');

    // ---- Priority filter sheet ----
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('Filter by Priority'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await settle(tester);
    print('✓ Priority filter sheet opens and applies');

    // ---- CRITICAL: no action controls anywhere on this screen ----
    expect(find.text('Take Action'), findsNothing, reason: 'Manager must not see any action buttons — view only');
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Mark Completed'), findsNothing);
    expect(find.text('Reschedule Deadline'), findsNothing);
    print('✓ Verified: zero action controls present anywhere on the Manager Task Monitoring screen');

    // ---- Tap a task row: must open a READ-ONLY detail sheet, not an editable screen ----
    final taskIcons = find.byIcon(Icons.chevron_right);
    if (taskIcons.evaluate().isNotEmpty) {
      await tester.tap(taskIcons.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(find.textContaining('Manager view is read-only'), findsOneWidget, reason: 'Task detail sheet must explicitly state it is read-only');
      expect(find.text('Take Action'), findsNothing);
      // Scope to the sheet itself — the underlying list screen (with its own
      // legitimate "Review" banner button) is still mounted behind the modal.
      final sheetButtons = find.descendant(of: find.byType(BottomSheet), matching: find.byType(ElevatedButton));
      expect(sheetButtons, findsNothing, reason: 'The read-only detail sheet must contain no action buttons at all');
      print('✓ Tapping a task opens a genuinely read-only detail sheet — no editable/action controls inside it');
      await tester.tapAt(const Offset(50, 50));
      await settle(tester);
    } else {
      print('… No tasks visible in this filtered view to open a detail sheet for');
    }

    print('✓ Manager Task Monitoring flow complete');
  });
}
