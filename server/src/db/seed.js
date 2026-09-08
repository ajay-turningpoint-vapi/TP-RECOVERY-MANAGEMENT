/**
 * Seeds a curated demo dataset for the automated test suite ONLY — every
 * `.test.js` file starts from this same fixture data via
 * test/helpers/db.js's resetDb(). This must never run against the real
 * app's database: the guard below refuses unconditionally unless
 * NODE_ENV=test and the configured database name contains "test", no
 * matter how it's invoked (via the test harness, `npm run seed`, or
 * `node src/db/seed.js` directly) — the real app's `customers`/`users`
 * tables hold real BUSY-sourced production data now (see
 * customerRepository.upsertFromBusy), and this dataset (C1-C5,
 * rahul/mahesh, etc.) must never overwrite it.
 */
const { query, withTransaction, closePool } = require('../config/db');
const { hashPassword } = require('../utils/password');
const logger = require('../config/logger');
const env = require('../config/env');

function assertTestDatabase() {
  if (!env.isTest) {
    throw new Error(
      'seed.js refuses to run without NODE_ENV=test — this dataset exists only for the automated test suite. Run tests via `npm test`.'
    );
  }
  if (!/test/i.test(env.db.database)) {
    throw new Error(
      `seed.js refuses to run — MARIADB_DATABASE ("${env.db.database}") doesn't look like a test database (expected a name containing "test"). ` +
        'This guard exists so a misconfigured run can never wipe the real app\'s BUSY-sourced production data.'
    );
  }
}

async function seed() {
  assertTestDatabase();
  logger.info('Seeding test database with demo dataset...');

  await withTransaction(async (conn) => {
    // Wipe in FK-safe order.
    for (const table of ['notifications', 'audit_events', 'payment_claims', 'escalation_cases', 'outcome_correction_requests', 'disputes', 'ptps', 'tasks', 'invoices', 'customers', 'users', 'daily_metrics_snapshot']) {
      await conn.query(`DELETE FROM \`${table}\``);
    }

    const passwordHash = await hashPassword('1234');

    const users = [
      { id: 'rahul', username: 'rahul', role: 'SALESPERSON', fullName: 'Rahul Sharma', designation: 'Sales Executive', branch: 'Mumbai', phone: '98765 43215', recoveryScore: 82, callsTarget: 18 },
      { id: 'mahesh', username: 'mahesh', role: 'SALESPERSON', fullName: 'Mahesh Patel', designation: 'Sales Executive', branch: 'Nagpur', phone: '98765 43219', recoveryScore: 88, callsTarget: 12 },
      // branch is NOT NULL now (migration 011) — RE/Management have no real
      // branch concept (same as production), so this matches the real DB's
      // own convention rather than the column's plain default.
      { id: 'amit-re', username: 'amit.re', role: 'RECOVERY_EXECUTIVE', fullName: 'Amit Mehra', designation: 'Recovery Executive', branch: 'Turning Point', phone: null, recoveryScore: 75, callsTarget: 0 },
      { id: 'ramesh-re', username: 'ramesh.re', role: 'RECOVERY_EXECUTIVE', fullName: 'Ramesh Kumar', designation: 'Recovery Executive', branch: 'Turning Point', phone: null, recoveryScore: 75, callsTarget: 0 },
      { id: 'suresh-mgr', username: 'suresh.mgr', role: 'MANAGEMENT', fullName: 'Suresh Iyer', designation: 'Regional Manager', branch: 'Turning Point', phone: null, recoveryScore: 75, callsTarget: 0 },
    ];

    for (const u of users) {
      await conn.query(
        'INSERT INTO users (id, username, password_hash, role, full_name, designation, branch, phone, recovery_score, calls_target) VALUES (:id, :username, :passwordHash, :role, :fullName, :designation, :branch, :phone, :recoveryScore, :callsTarget)',
        { ...u, passwordHash }
      );
    }

    const customers = [
      { id: 'C1', name: 'ABC Traders', assignedSalesmanId: 'rahul', branch: 'Mumbai', totalOutstanding: 500000, totalDue: 400000, oldestOverdueDays: 45, state: 'Action Required', action: 'CALL CUSTOMER', reason: 'Overdue follow-up', escalation: 'none' },
      { id: 'C2', name: 'XYZ Enterprises', assignedSalesmanId: 'rahul', branch: 'Mumbai', totalOutstanding: 350000, totalDue: 300000, oldestOverdueDays: 20, state: 'Action Required', action: 'CALL CUSTOMER', reason: 'Overdue follow-up', escalation: 'none' },
      { id: 'C3', name: 'PQR Stores', assignedSalesmanId: 'rahul', branch: 'Mumbai', totalOutstanding: 45000, totalDue: 45000, oldestOverdueDays: 10, state: 'Action Required', action: 'CALL CUSTOMER', reason: 'Overdue follow-up', escalation: 'none' },
      { id: 'C4', name: 'Metro Motors', assignedSalesmanId: 'mahesh', branch: 'Nagpur', totalOutstanding: 750000, totalDue: 750000, oldestOverdueDays: 75, state: 'Action Required', action: 'CALL CUSTOMER', reason: 'Broken PTP — urgent follow-up required', escalation: 'L2' },
      { id: 'C5', name: 'Om Sai Enterprises', assignedSalesmanId: 'mahesh', branch: 'Nagpur', totalOutstanding: 60000, totalDue: 60000, oldestOverdueDays: 15, state: 'Action Required', action: 'CALL CUSTOMER', reason: 'Dispute under review', escalation: 'none', disputedAmount: 25000 },
    ];

    for (const c of customers) {
      await conn.query(
        `INSERT INTO customers (id, name, branch, assigned_salesman_id, total_outstanding, total_due, oldest_overdue_days, current_recovery_state, primary_next_action, reason_for_action, escalation_level, disputed_amount)
         VALUES (:id, :name, :branch, :assignedSalesmanId, :totalOutstanding, :totalDue, :oldestOverdueDays, :state, :action, :reason, :escalation, :disputedAmount)`,
        { disputedAmount: 0, ...c }
      );
    }

    await conn.query(
      `INSERT INTO invoices (id, customer_id, invoice_number, amount, status) VALUES
        ('INV-C2-1', 'C2', 'INV-2024-501', 200000, 'Overdue'),
        ('INV-C2-2', 'C2', 'INV-2024-502', 100000, 'Due Soon'),
        ('INV-C3-1', 'C3', 'INV-2024-601', 80000, 'Partially Paid')`
    );

    const tasks = [
      { id: 'T1', type: 'physicalVisit', customerId: 'C1', ownerId: 'rahul', deadline: '2026-08-27 18:00:00', priority: 'High', reason: 'Customer not answering calls — physical visit required' },
      { id: 'T2', type: 'customerCall', customerId: 'C2', ownerId: 'rahul', deadline: '2026-08-27 18:00:00', priority: 'Normal', reason: 'Follow up on scheduled PTP' },
      { id: 'T3', type: 'customerCall', customerId: 'C4', ownerId: 'mahesh', deadline: '2026-08-27 18:00:00', priority: 'Critical', reason: 'Broken PTP — urgent follow-up required' },
      { id: 'T4', type: 'financialTeamFollowUp', customerId: 'C5', ownerId: 'ramesh-re', deadline: '2026-08-27 18:00:00', priority: 'High', reason: 'Verify disputed invoice amount with finance team' },
    ];
    for (const t of tasks) {
      await conn.query(
        'INSERT INTO tasks (id, type, customer_id, owner_id, deadline, priority, reason) VALUES (:id, :type, :customerId, :ownerId, :deadline, :priority, :reason)',
        t
      );
    }

    const ptps = [
      { id: 'P1', customerId: 'C1', amount: 150000, date: '2026-08-30 12:00:00', mode: 'Bank Transfer', status: 'scheduled', dueAtPromise: 400000, outstandingAtPromise: 500000 },
      { id: 'P2', customerId: 'C2', amount: 100000, date: '2026-08-29 12:00:00', mode: 'UPI', status: 'scheduled', dueAtPromise: 300000, outstandingAtPromise: 350000 },
      { id: 'P3', customerId: 'C3', amount: 35000, date: '2026-08-15 12:00:00', mode: 'Cash', status: 'kept', dueAtPromise: 80000, outstandingAtPromise: 80000 },
      { id: 'P4', customerId: 'C4', amount: 300000, date: '2026-08-10 12:00:00', mode: 'Cheque', status: 'broken', dueAtPromise: 750000, outstandingAtPromise: 750000 },
      { id: 'P5', customerId: 'C5', amount: 60000, date: '2026-08-31 12:00:00', mode: 'Bank Transfer', status: 'scheduled', dueAtPromise: 60000, outstandingAtPromise: 60000 },
    ];
    for (const p of ptps) {
      await conn.query(
        `INSERT INTO ptps (id, customer_id, amount_promised, promise_date, payment_mode, status, total_due_at_promise, total_outstanding_at_promise)
         VALUES (:id, :customerId, :amount, :date, :mode, :status, :dueAtPromise, :outstandingAtPromise)`,
        p
      );
    }

    await conn.query(
      `INSERT INTO disputes (id, customer_id, amount, total_due_at_raise, reason, status, priority, invoice_number)
       VALUES ('D_001', 'C5', 25000, 60000, 'Goods received damaged — partial credit note requested', 'Pending Approval', 'Medium', 'INV-2024-701')`
    );

    await conn.query(
      `INSERT INTO audit_events (customer_id, type, description, actor, source) VALUES
        ('C1', 'SEEDED', 'Account onboarded into recovery workflow.', 'System', 'Seed'),
        ('C2', 'SEEDED', 'Account onboarded into recovery workflow.', 'System', 'Seed'),
        ('C3', 'SEEDED', 'Account onboarded into recovery workflow.', 'System', 'Seed'),
        ('C4', 'SEEDED', 'Account onboarded into recovery workflow. Escalated to L2 after a broken PTP.', 'System', 'Seed'),
        ('C5', 'SEEDED', 'Account onboarded into recovery workflow. Dispute raised on invoice INV-2024-701.', 'System', 'Seed')`
    );
  });

  logger.info('Seed complete: 5 users, 5 customers, 3 invoices, 4 tasks, 5 PTPs, 1 dispute, 5 audit events.');
}

module.exports = { seed };

if (require.main === module) {
  seed()
    .then(() => closePool())
    .then(() => process.exit(0))
    .catch(async (err) => {
      logger.error('Seed failed', { message: err.message, stack: err.stack });
      await closePool();
      process.exit(1);
    });
}
