// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the two features that were previously local-only client state with
// zero server persistence:
//   1. Outcome Correction Requests (server/src/services/outcomeCorrectionService.js)
//   2. Dispute Resolution Verification (disputeService.resolve)
//
// Uses C1 for outcome corrections (captures the customer's actual current
// primaryNextAction/reasonForAction right before requesting, rather than
// assuming a fixed seed value — other integration test files also touch C1)
// and C4 for dispute resolution (a fresh dispute is raised specifically for
// this test, so it doesn't collide with anything else).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('a salesperson can request an outcome correction, and the original values are captured server-side, not client-supplied', () async {
    final rahul = AppStore();
    await rahul.loginWithApi('rahul', '1234');
    final before = rahul.customers.firstWhere((c) => c.id == 'C1');

    await rahul.requestOutcomeCorrection('C1', 'Follow-up', 'Fixed the recorded reason', 'Wrong reason was recorded during the call');

    final req = rahul.outcomeCorrectionRequests.firstWhere((r) => r.customerId == 'C1' && r.status == 'Pending');
    expect(req.salesmanId, 'rahul');
    expect(req.originalOutcome, before.primaryNextAction);
    expect(req.originalReason, before.reasonForAction);
    expect(req.requestedOutcome, 'Follow-up');

    final customer = rahul.customers.firstWhere((c) => c.id == 'C1');
    expect(customer.auditHistory.any((e) => e.type == 'SALESPERSON_REQUESTED_OUTCOME_CORRECTION'), isTrue);

    // A different salesperson must never be able to request a correction on
    // a customer outside their own portfolio.
    final mahesh = AppStore();
    await mahesh.loginWithApi('mahesh', '1234');
    expect(() => mahesh.requestOutcomeCorrection('C1', 'x', 'x', 'x'), throwsA(anything));
  });

  test('RE approving an outcome correction genuinely rewrites the customer\'s recorded outcome, and it can only be decided once', () async {
    final mahesh = AppStore();
    await mahesh.loginWithApi('mahesh', '1234');
    await mahesh.requestOutcomeCorrection('C4', 'Follow-up', 'Customer asked to call back tomorrow', 'Recorded the wrong reason during the call');
    final pending = mahesh.outcomeCorrectionRequests.firstWhere((r) => r.customerId == 'C4' && r.status == 'Pending');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.approveOutcomeCorrection(pending.id);

    final customer = re.customers.firstWhere((c) => c.id == 'C4');
    expect(customer.primaryNextAction, 'Follow-up');
    expect(customer.reasonForAction, 'Customer asked to call back tomorrow');
    expect(customer.auditHistory.any((e) => e.type == 'RE_APPROVED_OUTCOME_CORRECTION'), isTrue);

    // Already decided — approving again must be rejected.
    expect(() => re.approveOutcomeCorrection(pending.id), throwsA(anything));

    // A salesperson must never be able to approve/reject a request themselves.
    final rahul = AppStore();
    await rahul.loginWithApi('rahul', '1234');
    expect(() => rahul.approveOutcomeCorrection(pending.id), throwsA(anything));
  });

  test('RE rejecting an outcome correction leaves the customer\'s recorded outcome unchanged', () async {
    final rahul = AppStore();
    await rahul.loginWithApi('rahul', '1234');
    await rahul.requestOutcomeCorrection('C2', 'Follow-up', 'x', 'Trying to change the recorded outcome');
    final pending = rahul.outcomeCorrectionRequests.firstWhere((r) => r.customerId == 'C2' && r.status == 'Pending');
    final before = rahul.customers.firstWhere((c) => c.id == 'C2');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.rejectOutcomeCorrection(pending.id, 'Original outcome was accurate');

    final rejected = re.outcomeCorrectionRequests.firstWhere((r) => r.id == pending.id);
    expect(rejected.status, 'Rejected');

    final after = re.customers.firstWhere((c) => c.id == 'C2');
    expect(after.primaryNextAction, before.primaryNextAction);
    expect(after.reasonForAction, before.reasonForAction);
  });

  test('resolving an Approved dispute as Resolved genuinely reduces totalDue by the disputed amount, and it can only be verified once', () async {
    final mahesh = AppStore();
    await mahesh.loginWithApi('mahesh', '1234');
    await mahesh.recordOutcome('C4', 'Dispute Raised', 'Dispute Raised', 'Reason: Wrong pricing applied, Amt: 12000');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final dispute = re.disputes.firstWhere((d) => d['customerCode'] == 'C4' && d['status'] == 'Pending Approval' && d['amount'] == 12000.0);

    // A real 400 before Approved — resolving/verifying is only meaningful
    // once RE has already approved the dispute.
    expect(() => re.resolveDispute(dispute['id'] as String, 'Resolved'), throwsA(anything));

    await re.approveDispute(dispute['id'] as String, 'ramesh-re', DateTime.now().add(const Duration(days: 2)), 'Verify with warehouse');
    final before = re.customers.firstWhere((c) => c.id == 'C4');

    await re.resolveDispute(dispute['id'] as String, 'Resolved', note: 'Confirmed via BUSY');

    final resolved = re.disputes.firstWhere((d) => d['id'] == dispute['id']);
    expect(resolved['status'], 'Resolved');

    final after = re.customers.firstWhere((c) => c.id == 'C4');
    expect(after.totalDue, before.totalDue - 12000, reason: 'the real disputed amount must genuinely reduce exposure, not just relabel the dispute');
    expect(after.auditHistory.any((e) => e.type == 'RE_RESOLVED_DISPUTE'), isTrue);

    // Already resolved — verifying again must be rejected.
    expect(() => re.resolveDispute(dispute['id'] as String, 'Resolved'), throwsA(anything));
  });

  test('resolving an Approved dispute as Returned to Recovery leaves totalDue untouched, and a salesperson cannot verify a dispute', () async {
    final mahesh = AppStore();
    await mahesh.loginWithApi('mahesh', '1234');
    await mahesh.recordOutcome('C5', 'Dispute Raised', 'Dispute Raised', 'Reason: Damaged in transit, Amt: 8000');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final dispute = re.disputes.firstWhere((d) => d['customerCode'] == 'C5' && d['status'] == 'Pending Approval' && d['amount'] == 8000.0);
    await re.approveDispute(dispute['id'] as String, 'ramesh-re', DateTime.now().add(const Duration(days: 2)), 'Verify with warehouse');
    final before = re.customers.firstWhere((c) => c.id == 'C5');

    await re.resolveDispute(dispute['id'] as String, 'Returned to Recovery', note: 'Still unpaid');

    final after = re.customers.firstWhere((c) => c.id == 'C5');
    expect(after.totalDue, before.totalDue, reason: 'nothing was actually received — totalDue must not move');
    expect(after.auditHistory.any((e) => e.type == 'RE_RETURNED_DISPUTE_TO_RECOVERY'), isTrue);

    final rahul = AppStore();
    await rahul.loginWithApi('rahul', '1234');
    expect(() => rahul.resolveDispute('D_001', 'Resolved'), throwsA(anything));
  });
}
