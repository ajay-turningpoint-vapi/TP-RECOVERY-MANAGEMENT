// Seed data modeled on the Dart BusySimulator's seed set — realistic
// customers/PTPs/tasks so the engine can be exercised meaningfully without
// a real database. Replace with real DB-backed fetches in repository.js
// once the API/DB layer exists; nothing outside this file should need to
// change shape-wise if that swap is done carefully.

export function buildSeedCustomers() {
  return [
    {
      id: 'C001',
      name: 'Sharma Hardware Traders',
      totalOutstanding: 185000,
      totalDue: 185000,
      oldestOverdueDays: 12,
      currentRecoveryState: 'Waiting / Monitoring',
      primaryNextAction: 'CALL CUSTOMER',
      reasonForAction: 'Follow-up on outstanding balance',
      assignedSalesmanId: 'Rahul',
      contactNumber: '9876500001',
      escalationLevel: 'none',
      hasValidNextAction: true,
      ownerMappingRequired: false,
      isBusySyncHealthy: true,
    },
    {
      id: 'C002',
      name: 'Vijay Steel Works',
      totalOutstanding: 420000,
      totalDue: 420000,
      oldestOverdueDays: 34,
      currentRecoveryState: 'Waiting / Monitoring',
      primaryNextAction: 'CALL CUSTOMER',
      reasonForAction: 'High value overdue account',
      assignedSalesmanId: 'Rahul',
      contactNumber: '9876500002',
      escalationLevel: 'none',
      hasValidNextAction: true,
      ownerMappingRequired: false,
    },
    {
      id: 'C003',
      name: 'Krishna Builders & Co',
      totalOutstanding: 95000,
      totalDue: 95000,
      oldestOverdueDays: 8,
      currentRecoveryState: 'Waiting / Monitoring',
      primaryNextAction: 'CALL CUSTOMER',
      reasonForAction: 'Routine follow-up',
      assignedSalesmanId: 'Mahesh',
      contactNumber: '9876500003',
      escalationLevel: 'none',
      hasValidNextAction: true,
      ownerMappingRequired: false,
    },
    {
      id: 'C004',
      name: 'Om Enterprises',
      totalOutstanding: 260000,
      totalDue: 260000,
      oldestOverdueDays: 45,
      currentRecoveryState: 'Waiting / Monitoring',
      primaryNextAction: 'CALL CUSTOMER',
      reasonForAction: 'Repeated broken promises',
      assignedSalesmanId: 'Mahesh',
      contactNumber: '9876500004',
      escalationLevel: 'none',
      hasValidNextAction: true,
      ownerMappingRequired: false,
    },
    {
      id: 'C005',
      name: 'Ganesh Distributors',
      totalOutstanding: 62000,
      totalDue: 62000,
      oldestOverdueDays: 3,
      currentRecoveryState: 'Waiting / Monitoring',
      primaryNextAction: 'CALL CUSTOMER',
      reasonForAction: 'New overdue',
      assignedSalesmanId: 'Rahul',
      contactNumber: '9876500005',
      escalationLevel: 'none',
      hasValidNextAction: true,
      ownerMappingRequired: false,
    },
  ];
}

export function buildSeedSalesmen() {
  return [
    { id: 'Rahul', name: 'Rahul', role: 'SALESPERSON' },
    { id: 'Mahesh', name: 'Mahesh', role: 'SALESPERSON' },
    { id: 'Amit', name: 'Amit', role: 'RECOVERY_EXECUTIVE' },
    { id: 'Suresh', name: 'Suresh', role: 'MANAGEMENT' },
  ];
}
