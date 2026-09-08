// Real, cross-cutting system verification — hits the live TP-RMS server on
// 127.0.0.1:4000. Individual domains (tasks, PTPs, disputes, escalations,
// notifications, payment claims) already have dedicated integration test
// files; this file instead proves the *engines work together* across all 3
// roles (SALESPERSON, RECOVERY_EXECUTIVE, MANAGEMENT):
//   - the recovery-priority/scoring engine (AppStore.compareByRecoveryPriority)
//   - role-based data scoping (task engine + customer/dispute/escalation APIs)
//   - the PTP scheduling + maturity/reconciliation engine, on both a
//     past-due and a future-due promise
//   - the escalation engine driving the notification engine end-to-end,
//     read by a *different* user than the one who triggered it
//
// Customer choice avoids known collisions with other integration test
// files in this shared dev DB (see ptp_maturity_api_integration_test.dart's
// header comment for the general pattern): C4 (Mahesh's customer) is the
// only one of the 5 seed customers whose totalDue no other test file ever
// changes, so it's used here for the one exact-delta assertion.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';
import 'package:salesman_mobile/v2/models/notification_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  group('Priority/scoring engine (offline, deterministic)', () {
    Customer c({required String id, String esc = 'none', int overdue = 0, double due = 0}) => Customer(
          id: id,
          name: id,
          totalOutstanding: due,
          totalDue: due,
          oldestOverdueDays: overdue,
          currentRecoveryState: 'Action Required',
          primaryNextAction: 'CALL CUSTOMER',
          reasonForAction: 'Overdue follow-up',
          assignedSalesmanId: 'test',
          escalationLevel: esc,
        );

    test('escalation severity always outranks overdue days and amount due', () {
      final escalatedButFresh = c(id: 'A', esc: 'L1', overdue: 1, due: 100);
      final notEscalatedButOld = c(id: 'B', esc: 'none', overdue: 500, due: 999999);
      final list = [notEscalatedButOld, escalatedButFresh]..sort(AppStore.compareByRecoveryPriority);
      expect(list.first.id, 'A', reason: 'even a bare L1 must outrank a non-escalated customer no matter how overdue or large');
    });

    test('among equal escalation, more overdue days wins', () {
      final older = c(id: 'OLD', esc: 'L2', overdue: 90, due: 1000);
      final newer = c(id: 'NEW', esc: 'L2', overdue: 10, due: 1000000);
      final list = [newer, older]..sort(AppStore.compareByRecoveryPriority);
      expect(list.first.id, 'OLD');
    });

    test('among equal escalation and overdue days, larger amount due wins', () {
      final small = c(id: 'SMALL', esc: 'none', overdue: 10, due: 1000);
      final big = c(id: 'BIG', esc: 'none', overdue: 10, due: 500000);
      final list = [small, big]..sort(AppStore.compareByRecoveryPriority);
      expect(list.first.id, 'BIG');
    });

    test('higher escalation level always outranks a lower one, L1 through L4', () {
      final levels = ['L4', 'L3', 'L2', 'L1', 'none'];
      final shuffled = ['none', 'L2', 'L4', 'L1', 'L3'].map((l) => c(id: l, esc: l)).toList()..sort(AppStore.compareByRecoveryPriority);
      expect(shuffled.map((x) => x.id).toList(), levels);
    });
  });

  group('Cross-role data scoping', () {
    test('tasks, customers, disputes, and escalations are scoped correctly and consistently for all 3 roles', () async {
      final rahul = AppStore();
      await rahul.loginWithApi('rahul', '1234');
      final mahesh = AppStore();
      await mahesh.loginWithApi('mahesh', '1234');
      final re = AppStore();
      await re.loginWithApi('amit.re', '1234');
      final mgr = AppStore();
      await mgr.loginWithApi('suresh.mgr', '1234');

      // Salespersons: every customer/task/dispute they can see is genuinely
      // theirs — never another salesperson's data leaking through.
      for (final store in [rahul, mahesh]) {
        final myId = store.currentSalesmanId;
        expect(store.myCustomers.every((c) => c.assignedSalesmanId == myId), isTrue, reason: 'a salesperson must only see their own customers');
        expect(store.tasks.every((t) => t.ownerId == myId), isTrue, reason: 'a salesperson must only see tasks assigned to them');
        final myCustomerIds = store.myCustomers.map((c) => c.id).toSet();
        expect(store.disputes.every((d) => myCustomerIds.contains(d['customerCode'])), isTrue, reason: 'a salesperson must only see disputes on their own customers');
        expect(store.escalationCases.every((e) => myCustomerIds.contains(e.customerId)), isTrue, reason: 'a salesperson must only see escalations on their own customers');
      }

      // RE and Management: full visibility across the whole book, spanning
      // more than one salesperson's customers — proving this isn't just an
      // accidentally-narrow filter that happens to match one salesperson.
      for (final store in [re, mgr]) {
        expect(store.customers.length, 5, reason: 'RE/Management must see the entire customer book');
        final ownersOfVisibleTasks = store.tasks.map((t) => t.ownerId).toSet();
        expect(ownersOfVisibleTasks.length, greaterThan(1), reason: 'RE/Management must see tasks across multiple salespeople, not one filtered subset');
        final assignedSalesmen = store.customers.map((c) => c.assignedSalesmanId).toSet();
        expect(assignedSalesmen.length, greaterThan(1), reason: 'RE/Management customer visibility must span more than one salesperson');
      }
    });

    test('a salesperson cannot see or act on another role\'s privileged data — RBAC surfaces as real errors', () async {
      final rahul = AppStore();
      await rahul.loginWithApi('rahul', '1234');
      // Mutating actions reserved for RE/Management must be rejected for a salesperson.
      await expectLater(() => rahul.takeREControl('C1'), throwsA(anything));
      await expectLater(() => rahul.escalateCustomer('C4', 'L1', 'x', 'y', 'rahul', DateTime.now()), throwsA(anything));
    });
  });

  group('PTP scheduling + maturity engine — past and future promise dates', () {
    test('a past-due and a future-due PTP on the same customer are both correctly scheduled and reconciled, and totalDue reflects the exact real amounts received', () async {
      final mahesh = AppStore();
      await mahesh.loginWithApi('mahesh', '1234');

      final pastDate = DateTime.now().subtract(const Duration(days: 3));
      final futureDate = DateTime.now().add(const Duration(days: 10));
      const pastAmount = 77001.0;
      const futureAmount = 77002.0;

      await mahesh.recordOutcome('C4', 'PTP Scheduled', 'Agreed to clear an old overdue promise', 'PTP amount: $pastAmount',
          ptpAmountValue: pastAmount, ptpDate: pastDate, ptpMode: 'Cash');
      await mahesh.recordOutcome('C4', 'PTP Scheduled', 'Agreed to a fresh future promise', 'PTP amount: $futureAmount',
          ptpAmountValue: futureAmount, ptpDate: futureDate, ptpMode: 'UPI');

      final pastPtp = mahesh.ptps.firstWhere((p) => p.customerId == 'C4' && p.amountPromised == pastAmount);
      final futurePtp = mahesh.ptps.firstWhere((p) => p.customerId == 'C4' && p.amountPromised == futureAmount);
      expect(pastPtp.promiseDate.isBefore(DateTime.now()), isTrue, reason: 'the scheduling engine must store a genuinely past date as given, not clamp it to today');
      expect(futurePtp.promiseDate.isAfter(DateTime.now()), isTrue);
      expect(pastPtp.status, PtpStatus.scheduled);
      expect(futurePtp.status, PtpStatus.scheduled);

      final re = AppStore();
      await re.loginWithApi('amit.re', '1234');
      final before = re.customers.firstWhere((c) => c.id == 'C4').totalDue;

      await re.markPtpOutcome(pastPtp.id, 'kept', amountReceived: pastAmount);
      await re.markPtpOutcome(futurePtp.id, 'partiallyKept', amountReceived: 30000);

      final after = re.customers.firstWhere((c) => c.id == 'C4').totalDue;
      expect(after, before - pastAmount - 30000, reason: 'both a past-scheduled and a future-scheduled PTP must genuinely reduce exposure by the real amount received, regardless of which direction the promise date pointed');

      final reconciledPast = re.ptps.firstWhere((p) => p.id == pastPtp.id);
      final reconciledFuture = re.ptps.firstWhere((p) => p.id == futurePtp.id);
      expect(reconciledPast.status, PtpStatus.kept);
      expect(reconciledPast.amountReceived, pastAmount);
      expect(reconciledFuture.status, PtpStatus.partiallyKept);
      expect(reconciledFuture.amountReceived, 30000);

      final customer = re.customers.firstWhere((c) => c.id == 'C4');
      expect(customer.auditHistory.where((e) => e.type == 'PTP_KEPT_PAYMENT_APPLIED' || e.type == 'PTP_PARTIALLY_KEPT_PAYMENT_APPLIED').length, greaterThanOrEqualTo(2), reason: 'both reconciliations must be genuinely recorded in the customer report/audit trail');
    });
  });

  group('Escalation engine -> notification engine, across roles', () {
    Future<NotificationItem> waitForNotification(AppStore store, String username, bool Function(NotificationItem) predicate) async {
      for (var i = 0; i < 20; i++) {
        await store.loginWithApi(username, '1234');
        final match = store.notifications.where(predicate);
        if (match.isNotEmpty) return match.first;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      throw StateError('Timed out waiting for notification to be delivered by the worker');
    }

    test('an RE-raised escalation is queued, delivered, and readable by the specific assigned owner — a different user than the one who raised it', () async {
      final marker = 'SYSCHECK-${DateTime.now().microsecondsSinceEpoch}';
      final re = AppStore();
      await re.loginWithApi('amit.re', '1234');
      await re.escalateCustomer('C2', 'L2', marker, 'Call daily until contact made', 'ramesh-re', DateTime.now().add(const Duration(days: 2)));

      final owner = AppStore();
      final notification = await waitForNotification(owner, 'ramesh.re', (n) => n.customerId == 'C2' && n.body == marker);
      expect(notification.severity, NotificationSeverity.warning);
      expect(notification.read, isFalse);

      // Raising a strictly-less-severe case afterward must never downgrade
      // the customer's escalation badge below what's already open.
      final beforeDowngradeAttempt = owner.customers.firstWhere((c) => c.id == 'C2').escalationLevel;
      await re.escalateCustomer('C2', 'L1', 'a lower-severity case must not downgrade', 'plan', 'ramesh-re', DateTime.now().add(const Duration(days: 1)));
      final afterDowngradeAttempt = re.customers.firstWhere((c) => c.id == 'C2').escalationLevel;
      const severity = {'none': 0, 'L1': 1, 'L2': 2, 'L3': 3, 'L4': 4};
      expect(severity[afterDowngradeAttempt]!, greaterThanOrEqualTo(severity[beforeDowngradeAttempt]!), reason: 'escalation severity must never regress');

      await owner.markNotificationRead(notification.id);
      final afterRead = owner.notifications.firstWhere((n) => n.id == notification.id);
      expect(afterRead.read, isTrue);

      // A different, uninvolved salesperson must never see or be able to
      // touch this notification.
      final uninvolved = AppStore();
      await uninvolved.loginWithApi('rahul', '1234');
      expect(uninvolved.notifications.any((n) => n.id == notification.id), isFalse, reason: 'notifications must be strictly per-user — rahul was never the target of this escalation');

      // Clean up both cases raised in this test so this file doesn't leave
      // permanently-open escalations behind for future runs to trip over.
      for (final case_ in re.escalationCases.where((e) => e.customerId == 'C2' && e.isOpen && (e.reason == marker || e.reason.contains('must not downgrade')))) {
        await re.resolveEscalation(case_.id, 'System-wide verification test cleanup');
      }
    });
  });
}
