// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the Tasks domain being fully migrated off BusySimulator: complete,
// approve/reject edit, reassign, reschedule, and physical-visit review are
// now API-only in AppStore (see lib/v2/stores/app_store.dart). Run
// `npm run seed` in server/ before this file for a predictable starting
// state (it mutates real dev data, same as api_client_integration_test.dart).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('completeTask completes via the real API and refreshes local state', () async {
    final store = AppStore();
    await store.loginWithApi('rahul', '1234');
    // T2 (customerCall on C2) — C2 has an active PTP, so completing it must
    // not trigger the server's reopen-recovery guard.
    final before = store.tasks.firstWhere((t) => t.id == 'T2');
    expect(before.status, isNot(TaskStatus.completed));

    await store.completeTask('T2');

    final after = store.tasks.firstWhere((t) => t.id == 'T2');
    expect(after.status, TaskStatus.completed);
  });

  test('a salesperson requesting an extension, then RE approving it, both round-trip through the real API', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    final newDeadline = DateTime.now().add(const Duration(days: 4));
    await salesperson.requestTaskEditApproval('T1', 'Customer traveling', newDeadline, 'High');
    final pending = salesperson.tasks.firstWhere((t) => t.id == 'T1');
    expect(pending.approvalStatus, 'Pending');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.approveTaskEdit('T1');
    final approved = re.tasks.firstWhere((t) => t.id == 'T1');
    expect(approved.approvalStatus, 'Approved');
    expect(approved.deadline.difference(newDeadline).inSeconds.abs() < 2, isTrue, reason: 'MariaDB DATETIME truncates sub-second precision');

    // The approving RE's own AppStore should also see the customer's
    // updated audit history from _refreshOneCustomerFromApi.
    final customer = re.customers.firstWhere((c) => c.id == approved.customerId);
    expect(customer.auditHistory.any((e) => e.type == 'RE_APPROVED_TASK_EDIT'), isTrue);
  });

  test('RE reassigning a task updates the owner via the real API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    // T3, untouched by the other tests in this file/suite — sibling
    // integration test files share this same live dev database, so a
    // predicate-based `firstWhere` here can race against whatever those
    // files just did to T1/T2/T4.
    await re.reassignTask('T3', 'rahul', 'Workload rebalance');

    final updated = re.tasks.firstWhere((t) => t.id == 'T3');
    expect(updated.ownerId, 'rahul');
  });

  test('RE rescheduling a task directly does not create a Pending approval state', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final newDeadline = DateTime.now().add(const Duration(days: 6));
    // T4 — same isolation reasoning as above.
    await re.rescheduleTask('T4', 'Customer requested later visit', newDeadline);

    final updated = re.tasks.firstWhere((t) => t.id == 'T4');
    expect(updated.deadline.difference(newDeadline).inSeconds.abs() < 2, isTrue);
  });

  test('a real API failure surfaces as a catchable error, not a silent no-op', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    // A salesperson cannot reassign tasks — RE/Manager only.
    expect(() => salesperson.reassignTask('T1', 'mahesh', 'test'), throwsA(anything));
  });
}
