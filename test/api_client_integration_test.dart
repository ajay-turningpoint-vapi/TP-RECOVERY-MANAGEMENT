// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000
// (must be running, e.g. via `pm2 start ecosystem.config.js` in server/).
// Not a mock: proves the Dart-side JSON parsing (Customer.fromJson,
// AppTask.fromJson) actually matches what the real API returns, and that
// AppStore.loginWithApi/recordOutcome work end-to-end against real MariaDB.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/services/api_client.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // flutter_test installs a global HttpOverrides that intercepts every
  // request and returns a fake 400 with no real network call (it warns
  // about this explicitly) — this is a real integration test against the
  // live server, so that override must be disabled.
  HttpOverrides.global = null;

  test('ApiClient.login against the live server returns a real token and user', () async {
    final client = ApiClient();
    final user = await client.login('rahul', '1234');
    expect(user['username'], 'rahul');
    expect(user['role'], 'SALESPERSON');
  });

  test('ApiClient.login rejects a wrong password with a real 401', () async {
    final client = ApiClient();
    expect(
      () => client.login('rahul', 'wrong-password'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('AppStore.loginWithApi loads real customers scoped to the salesperson', () async {
    final store = AppStore();
    final error = await store.loginWithApi('rahul', '1234');
    expect(error, isNull);
    expect(store.userRole, 'SALESPERSON');
    expect(store.customers, isNotEmpty);
    expect(store.customers.every((c) => c.assignedSalesmanId == 'rahul'), isTrue);
    // myCustomers getter filters by currentSalesmanId — must actually work
    // with the real server's lowercase user id, not the old capitalized
    // 'Rahul' demo-data convention.
    expect(store.myCustomers.length, store.customers.length);
  });

  test('AppStore.recordOutcome (API-backed) creates a real PTP and updates the customer via the API', () async {
    final store = AppStore();
    await store.loginWithApi('rahul', '1234');
    final customerId = store.customers.first.id;
    final before = store.customersHandled;

    await store.recordOutcome(
      customerId,
      'PTP Scheduled',
      'Customer committed to pay',
      'Will pay by bank transfer',
      ptpAmountValue: 50000,
      ptpDate: DateTime.now().add(const Duration(days: 5)),
      ptpMode: 'UPI',
    );

    expect(store.customersHandled, before + 1);
    final updated = store.customers.firstWhere((c) => c.id == customerId);
    expect(updated.currentRecoveryState, 'Waiting / Monitoring');
    // Server writes a specific label per outcome (outcomeAuditLabel() in
    // customerService.js), mirroring the Dart client's own
    // _outcomeAuditLabel — not a generic "OUTCOME_RECORDED" placeholder.
    expect(updated.auditHistory.any((e) => e.type == 'Promise To Pay Recorded'), isTrue);
  });
}
