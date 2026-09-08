// Real integration test — hits the live TP-RMS server on 127.0.0.1:4000.
// Covers the RE customer-action domain being migrated off BusySimulator:
// takeREControl/releaseREControl/assignManagementInstruction/
// reassignCustomer are now API-only.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  test('RE taking control supersedes open tasks and puts the customer in RE Control via the real API', () async {
    // Create a dedicated, guaranteed-open task via record-outcome rather
    // than relying on C2's seed task — sibling integration test files
    // (e.g. tasks_api_integration_test.dart) mutate every seed task across
    // every customer, so a seed-data assumption here is fragile.
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    await salesperson.recordOutcome('C2', 'Follow-up', 'Customer asked to call back', 'Call back tomorrow');

    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final openBefore = re.tasks.where((t) => t.customerId == 'C2' && t.status != TaskStatus.completed && t.status != TaskStatus.closed);
    expect(openBefore, isNotEmpty);

    await re.takeREControl('C2');

    final customer = re.customers.firstWhere((c) => c.id == 'C2');
    expect(customer.currentRecoveryState, 'RE Control');
    expect(customer.auditHistory.any((e) => e.type == 'RE_TAKEN_CONTROL'), isTrue);
    final stillOpen = re.tasks.where((t) => t.customerId == 'C2' && t.status != TaskStatus.completed && t.status != TaskStatus.closed);
    expect(stillOpen, isEmpty);
  });

  test('RE releasing control returns the customer to Action Required via the real API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    await re.takeREControl('C3');

    await re.releaseREControl('C3');

    final customer = re.customers.firstWhere((c) => c.id == 'C3');
    expect(customer.currentRecoveryState, 'Action Required');
    expect(customer.auditHistory.any((e) => e.type == 'RE_RELEASED_CONTROL'), isTrue);
  });

  test('assignManagementInstruction creates a real task via the real API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');
    final deadline = DateTime.now().add(const Duration(days: 2));

    await re.assignManagementInstruction('C5', 'mahesh', 'Call director', deadline, priority: 'Critical');

    final customer = re.customers.firstWhere((c) => c.id == 'C5');
    expect(customer.auditHistory.any((e) => e.type == 'RE_CREATED_INSTRUCTION'), isTrue);
    final instruction = re.tasks.firstWhere((t) => t.customerId == 'C5' && t.type == TaskType.managementInstruction);
    expect(instruction.ownerId, 'mahesh');
    expect(instruction.reason, 'Call director');
  });

  test('reassignCustomer changes the assigned salesperson via the real API', () async {
    final re = AppStore();
    await re.loginWithApi('amit.re', '1234');

    await re.reassignCustomer('C3', 'rahul', 'mahesh', 'Rebalancing workload');

    final customer = re.customers.firstWhere((c) => c.id == 'C3');
    expect(customer.assignedSalesmanId, 'mahesh');
    expect(customer.auditHistory.any((e) => e.type == 'RE_CHANGED_OWNER'), isTrue);

    // Restore original ownership — this is shared dev/demo data, and other
    // test files (payment_claims, ptps) assume C3 stays rahul's customer.
    await re.reassignCustomer('C3', 'mahesh', 'rahul', 'Test cleanup — restoring original owner');
  });

  test('a salesperson cannot take control or reassign a customer — real 403s surface as catchable errors', () async {
    final salesperson = AppStore();
    await salesperson.loginWithApi('rahul', '1234');
    expect(() => salesperson.takeREControl('C1'), throwsA(anything));
    expect(() => salesperson.reassignCustomer('C1', 'rahul', 'mahesh', 'x'), throwsA(anything));
  });
}
