// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the manual-escalation domain being migrated off BusySimulator:
// escalateCustomer(autoTriggered: false)/resolveEscalation are now
// API-only. The autoTriggered path (broken-PTP auto-escalation, driven by
// the local-only BUSY sync simulation) deliberately stays local — see
// AppStore.escalateCustomer's doc comment.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('RE manually escalating a customer raises a real case and bumps escalationLevel via the API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final before = re.customers.firstWhere((c) => c.id == 'C1');
    expect(before.escalationLevel, 'none');

    final deadline = DateTime.now().add(const Duration(days: 2));
    await re.escalateCustomer('C1', 'L2', 'Customer unresponsive', 'Call daily until contact made', 'rahul', deadline);

    final after = re.customers.firstWhere((c) => c.id == 'C1');
    expect(after.escalationLevel, 'L2');
    final case_ = re.escalationCases.firstWhere((e) => e.customerId == 'C1' && e.isOpen);
    expect(case_.level, 'L2');
    expect(case_.ownerId, 'rahul');
  });

  test('resolving the last open escalation resets escalationLevel to none via the API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.escalateCustomer('C2', 'L1', 'Test escalation', 'Plan', 'rahul', DateTime.now().add(const Duration(days: 1)));
    final case_ = re.escalationCases.firstWhere((e) => e.customerId == 'C2' && e.isOpen);

    await re.resolveEscalation(case_.id, 'Customer responded, resolved');

    final customer = re.customers.firstWhere((c) => c.id == 'C2');
    expect(customer.escalationLevel, 'none');
    // GET /api/escalations for RE/Manager only returns open cases (see
    // escalationService.listForUser) — a just-resolved case correctly
    // disappears from this list, so there's nothing further to assert on
    // re.escalationCases here.
    expect(re.escalationCases.any((e) => e.id == case_.id && e.isOpen), isFalse);
  });

  test('a salesperson cannot manually escalate a customer — real 403 surfaces as a catchable error', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    expect(
      () => salesperson.escalateCustomer('C1', 'L1', 'test', 'plan', 'rahul', DateTime.now()),
      throwsA(anything),
    );
  });
}
