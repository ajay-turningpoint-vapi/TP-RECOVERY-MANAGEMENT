// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers Dispute Resolution Verification (disputeService.resolve).
//
// Uses C4/C5 for dispute resolution (fresh disputes are raised specifically
// for these tests, so they don't collide with anything else).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

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
