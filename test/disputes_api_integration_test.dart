// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the Disputes domain being migrated off BusySimulator:
// approveDispute/rejectDispute/requestDisputeInfo are now API-only, and
// AppStore.disputes is populated from the server's dispute JSON mapped
// onto the same Map shape (customer/totalDue/invoice/customerCode) every
// existing dispute screen already reads.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('disputes are populated from the real API in the shape existing screens expect', () async {
    final store = AppStore();
    await store.loginWithApi('amit.re', '1234');
    expect(store.disputes, isNotEmpty);
    final d = store.disputes.first;
    expect(d['id'], isNotNull);
    expect(d['customer'], isA<String>());
    expect(d['customerCode'], isA<String>());
    expect(d['amount'], isA<double>());
    expect(d['totalDue'], isA<double>());
    expect(d['raisedDate'], isA<DateTime>());
  });

  test('RE approving a dispute creates a real task and updates the customer via the API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final dispute = re.disputes.firstWhere((d) => d['id'] == 'D_001');
    final deadline = DateTime.now().add(const Duration(days: 2));

    await re.approveDispute('D_001', 'ramesh-re', deadline, 'Verify with warehouse');

    final updated = re.disputes.firstWhere((d) => d['id'] == 'D_001');
    expect(updated['status'], 'Approved');
    expect(updated['resolutionOwner'], 'ramesh-re');
    expect(re.tasks.any((t) => t.customerId == dispute['customerCode'] && t.ownerId == 'ramesh-re' && t.source == 'Dispute Review'), isTrue);

    final customer = re.customers.firstWhere((c) => c.id == dispute['customerCode']);
    expect(customer.auditHistory.any((e) => e.type == 'RE_APPROVED_DISPUTE'), isTrue);
  });

  test('RE rejecting a dispute records the reason via the real API', () async {
    // Raise a fresh dispute on C4 (Mahesh's customer) so it doesn't collide
    // with D_001, which the approve test above consumes.
    final salesperson = AppStore();
    await salesperson.loginWithApi('mahesh', '1234');
    await salesperson.recordOutcome('C4', 'Dispute Raised', 'Dispute Raised', 'Reason: Damaged goods, Amt: 6000');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final dispute = re.disputes.firstWhere((d) => d['customerCode'] == 'C4' && d['status'] == 'Pending Approval');

    await re.rejectDispute(dispute['id'] as String, 'No supporting evidence');

    final updated = re.disputes.firstWhere((d) => d['id'] == dispute['id']);
    expect(updated['status'], 'Rejected');
    expect(updated['rejectionReason'], 'No supporting evidence');
  });

  test('a real 403 from a salesperson trying to approve a dispute surfaces as a catchable error', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    expect(() => salesperson.approveDispute('D_001', 'ramesh-re', DateTime.now(), 'x'), throwsA(anything));
  });
}
