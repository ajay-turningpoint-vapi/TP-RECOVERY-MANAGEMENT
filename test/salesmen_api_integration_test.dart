// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the salesmen-roster domain: every figure (identity, Recovery
// Score, collection/task/PTP performance) is computed server-side (see
// server/src/services/salesmanService.js) — GET /api/salesmen, RE/Management
// only.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('RE sees a real salesmen roster keyed by the real user id, matching real customers', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');

    expect(re.salesmen, isNotEmpty);
    final rahul = re.salesmen.firstWhere((s) => s['name'] == 'rahul');
    expect(rahul['branch'], 'Mumbai');
    expect(rahul['empId'], 'rahul');

    final ownedByRahul = re.customers.where((c) => c.assignedSalesmanId == 'rahul').length;
    expect(rahul['customers'], ownedByRahul);
    expect(rahul['customers'], greaterThan(0));
  });

  test("a salesperson's own recovery score is computed against their real customers, not an empty portfolio", () async {
    final rahul = AppStore();
    await rahul.loginWithApi('rahul', '1234');
    final breakdown = rahul.myRecoveryScoreComponents;
    expect(breakdown, isNotNull);
    expect(breakdown!['total'], isNotNull);

    // The salesperson role has no access to GET /api/salesmen (RE/Management
    // only, matching the server's RBAC) — the roster stays empty for them
    // rather than throwing.
    expect(rahul.salesmen, isEmpty);
  });

  test('management can also list the real salesmen roster', () async {
    final manager = AppStore();
    await manager.loginWithApi('suresh.mgr', '1234');
    expect(manager.salesmen, isNotEmpty);
    expect(manager.salesmen.any((s) => s['name'] == 'mahesh'), isTrue);
  });
}
