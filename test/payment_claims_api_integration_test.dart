// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the Payment Claims domain being migrated off BusySimulator:
// verifyPaymentClaim is now API-only, and always resolves Verified/Failed
// — the old local "Sync Pending" branch (tied to the demo isBusySyncHealthy
// toggle) has no server equivalent.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('RE verifying a payment claim genuinely reduces the customer\'s real totalDue via the API', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    await salesperson.recordOutcome('C2', 'Verification Pending', 'Payment Already Made', 'Amount: ₹20000');
    final dueBefore = salesperson.customers.firstWhere((c) => c.id == 'C2').totalDue;

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final claim = re.paymentClaims.firstWhere((p) => p['customerCode'] == 'C2' && p['status'] == 'Awaiting Verification');

    await re.verifyPaymentClaim(claim['id'] as String, true);

    final updatedClaim = re.paymentClaims.firstWhere((p) => p['id'] == claim['id']);
    expect(updatedClaim['status'], 'Verified');
    final updatedCustomer = re.customers.firstWhere((c) => c.id == 'C2');
    expect(updatedCustomer.totalDue, dueBefore - 20000);
    expect(updatedCustomer.auditHistory.any((e) => e.type == 'PAYMENT_CLAIM_VERIFIED'), isTrue);
  });

  test('RE marking a claim Failed via the API leaves totalDue untouched', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('mahesh', '1234');
    await salesperson.recordOutcome('C5', 'Verification Pending', 'Payment Already Made', 'Amount: ₹10000');
    final dueBefore = salesperson.customers.firstWhere((c) => c.id == 'C5').totalDue;

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final claim = re.paymentClaims.firstWhere((p) => p['customerCode'] == 'C5' && p['status'] == 'Awaiting Verification');

    await re.verifyPaymentClaim(claim['id'] as String, false);

    final updated = re.customers.firstWhere((c) => c.id == 'C5');
    expect(updated.totalDue, dueBefore);
    expect(updated.auditHistory.any((e) => e.type == 'PAYMENT_CLAIM_FAILED'), isTrue);
  });

  test('a salesperson cannot verify a payment claim — real 403 surfaces as a catchable error', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    await salesperson.recordOutcome('C3', 'Verification Pending', 'Payment Already Made', 'Amount: ₹5000');
    final claim = salesperson.paymentClaims.firstWhere((p) => p['customerCode'] == 'C3' && p['status'] == 'Awaiting Verification');
    expect(() => salesperson.verifyPaymentClaim(claim['id'] as String, true), throwsA(anything));
  });
}
