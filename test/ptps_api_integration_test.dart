// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the PTP-correction domain being fully migrated off BusySimulator:
// requestPtpCorrection/approvePtpCorrection/rejectPtpCorrection are now
// API-only in AppStore. Uses distinct PTP ids per test (P1/P2/P3) since
// sibling integration test files share this same live dev database.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('requesting a PTP correction round-trips through the real API without changing the original commitment', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    final before = salesperson.ptps.firstWhere((p) => p.id == 'P1');

    final newDate = DateTime.now().add(const Duration(days: 8));
    await salesperson.requestPtpCorrection('P1', 175000, newDate, 'Customer revised commitment');

    final after = salesperson.ptps.firstWhere((p) => p.id == 'P1');
    expect(after.correctionStatus, 'Pending');
    expect(after.correctionRequestedAmount, 175000);
    expect(after.amountPromised, before.amountPromised, reason: 'original commitment must not change until approved');
  });

  test('RE approving a PTP correction applies the new amount via the real API', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    await salesperson.requestPtpCorrection('P2', 120000, DateTime.now().add(const Duration(days: 9)), 'Partial payment agreed');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.approvePtpCorrection('P2');

    final approved = re.ptps.firstWhere((p) => p.id == 'P2');
    expect(approved.correctionStatus, 'Approved');
    expect(approved.amountPromised, 120000);

    final customer = re.customers.firstWhere((c) => c.id == approved.customerId);
    expect(customer.auditHistory.any((e) => e.type == 'RE_APPROVED_PTP_CORRECTION'), isTrue);
  });

  test('RE rejecting a PTP correction leaves the original commitment untouched', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    final before = salesperson.ptps.firstWhere((p) => p.id == 'P3');
    await salesperson.requestPtpCorrection('P3', 999999, DateTime.now(), 'test');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.rejectPtpCorrection('P3', 'Amount looks implausible');

    final rejected = re.ptps.firstWhere((p) => p.id == 'P3');
    expect(rejected.correctionStatus, 'Rejected');
    expect(rejected.amountPromised, before.amountPromised);
  });

  test('a salesperson cannot approve or reject PTP corrections — real 403 surfaces as an error', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    expect(() => salesperson.approvePtpCorrection('P1'), throwsA(anything));
  });
}
