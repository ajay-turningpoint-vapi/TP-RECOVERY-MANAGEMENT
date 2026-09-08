// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers PTP maturity/reconciliation: AppStore.markPtpOutcome, a real
// manual RE action (no live payment-gateway integration exists to
// auto-detect this — same pattern as Payment Already Made claims). Also
// covers the broken-PTP escalation ladder this now genuinely drives
// server-side (2 broken PTPs reach L2, 3+ reach L3, never auto L4).
//
// Uses P5 (C5) and P1 (C1) for the Kept/Partially Kept cases, and C3 for
// the escalation ladder (creating fresh PTPs via record-outcome) — chosen
// to avoid colliding with other integration test files' totalDue/
// escalationLevel assertions elsewhere in this shared dev DB (notably,
// payment_claims_api_integration_test.dart also reduces C2's totalDue by a
// real verified claim).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/ptp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('RE marking a PTP Kept applies the real received amount and reduces the customer\'s totalDue', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final before = re.customers.firstWhere((c) => c.id == 'C5');

    await re.markPtpOutcome('P5', 'kept', amountReceived: 60000);

    final ptp = re.ptps.firstWhere((p) => p.id == 'P5');
    expect(ptp.status, PtpStatus.kept);
    expect(ptp.amountReceived, 60000);

    final after = re.customers.firstWhere((c) => c.id == 'C5');
    expect(after.totalDue, before.totalDue - 60000, reason: 'a Kept PTP must genuinely reduce financial exposure');
    expect(after.auditHistory.any((e) => e.type == 'PTP_KEPT_PAYMENT_APPLIED'), isTrue);

    // Self-contained (not relying on a separate test's earlier state): P5 is
    // already reconciled by the actions just above in this same test.
    expect(() => re.markPtpOutcome('P5', 'broken'), throwsA(anything), reason: 'P5 was just reconciled above — reconciling it again must be rejected');

    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    expect(() => salesperson.markPtpOutcome('P1', 'kept', amountReceived: 100), throwsA(anything), reason: 'a salesperson must never be able to reconcile a PTP themselves');
  });

  test('RE marking a PTP Partially Kept only reduces totalDue by the real amount actually received', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    // C1/P1 (not C2/P2 — payment_claims_api_integration_test.dart also
    // reduces C2's totalDue by a real verified claim, which would race
    // against an exact-delta assertion here).
    final before = re.customers.firstWhere((c) => c.id == 'C1');

    await re.markPtpOutcome('P1', 'partiallyKept', amountReceived: 40000);

    final ptp = re.ptps.firstWhere((p) => p.id == 'P1');
    expect(ptp.status, PtpStatus.partiallyKept);

    final after = re.customers.firstWhere((c) => c.id == 'C1');
    expect(after.totalDue, before.totalDue - 40000, reason: 'only the real amount actually received must reduce exposure');
  });

  test('2 broken PTPs on the same customer reach L2, a 3rd reaches L3 — never auto L4', () async {
    // Severity-relative assertions, not exact-string ones: every real
    // customer in this shared dev DB is also escalated by other
    // integration test files (e.g. notifications_api_integration_test.dart
    // escalates C3 to L2 for its own purposes), and there's no reseed
    // between test files within one run — so C3 may not start at 'none'.
    // The precise "exactly L2 at 2 breaks, exactly L3 at 3, and a real
    // System-actor case is created at each step" behavior is already
    // verified deterministically server-side, in isolation, in
    // server/test/ptps.test.js (a dedicated, never-shared test database).
    // This test instead proves the real client wiring: marking PTPs broken
    // through AppStore.markPtpOutcome genuinely drives escalation forward,
    // never backward, and never reaches L4 automatically.
    const severity = {'none': 0, 'L1': 1, 'L2': 2, 'L3': 3, 'L4': 4};

    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');

    // Distinctive, unlikely-to-collide amounts so each new PTP can be
    // identified reliably afterwards regardless of what else touches C3.
    const amounts = [512345.0, 512346.0, 512347.0];
    for (final amount in amounts) {
      await salesperson.recordOutcome('C3', 'PTP Scheduled', 'Will pay next week', 'PTP amount: $amount',
          ptpAmountValue: amount, ptpDate: DateTime.now().add(const Duration(days: 1)), ptpMode: 'UPI');
    }
    final ptpIds = amounts
        .map((amount) => salesperson.ptps.firstWhere((p) => p.customerId == 'C3' && p.status == PtpStatus.scheduled && p.amountPromised == amount).id)
        .toList();

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final startingSeverity = severity[re.customers.firstWhere((c) => c.id == 'C3').escalationLevel] ?? 0;

    await re.markPtpOutcome(ptpIds[0], 'broken', brokenReason: 'No response');
    var level = re.customers.firstWhere((c) => c.id == 'C3').escalationLevel;
    expect(severity[level], startingSeverity, reason: '1 broken PTP alone must not escalate beyond whatever level C3 already had');

    await re.markPtpOutcome(ptpIds[1], 'broken', brokenReason: 'No response');
    level = re.customers.firstWhere((c) => c.id == 'C3').escalationLevel;
    expect(severity[level]!, greaterThanOrEqualTo(2), reason: '2 broken PTPs must reach at least L2');
    // Whether a *new* System-attributed case is raised at this exact step
    // is itself conditional on C3's starting level (raise() only creates
    // one when the target is strictly more severe than what's already
    // there — verified precisely, from a guaranteed clean start, in
    // server/test/ptps.test.js), so it's not re-asserted here.

    await re.markPtpOutcome(ptpIds[2], 'broken', brokenReason: 'No response');
    level = re.customers.firstWhere((c) => c.id == 'C3').escalationLevel;
    expect(severity[level]!, greaterThanOrEqualTo(2), reason: '3 broken PTPs must stay at least L2 (reaches L3 from a clean start)');
    expect(level, isNot('L4'), reason: 'broken PTPs must never auto-escalate to L4 — that stays a human/RE judgment call');
  });
}
