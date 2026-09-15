const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');

let app;

before(async () => {
  await resetDb();
  app = await startTestApp();
});

after(async () => {
  await teardownAll(app);
});

test('customer detail invoices are camelCase, not raw snake_case SQL columns', async () => {
  const token = await login(app.baseUrl, 'rahul');
  // C2 has invoices in the seed data.
  const detail = await fetch(`${app.baseUrl}/api/customers/C2`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.ok(detail.invoices.length > 0);
  const invoice = detail.invoices[0];
  assert.ok(invoice.invoiceNumber, 'expected camelCase invoiceNumber, not snake_case invoice_number');
  assert.equal(invoice.invoice_number, undefined);
});

test('a salesperson only sees their own portfolio, not the whole book', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/customers`, { headers: authHeaders(token) });
  assert.equal(res.status, 200);
  const customers = await res.json();
  assert.ok(customers.length > 0);
  assert.ok(customers.every((c) => c.assignedSalesmanId === 'rahul'));
});

test('a salesperson cannot view another salesperson\'s customer directly', async () => {
  const token = await login(app.baseUrl, 'rahul');
  // C4 is Mahesh's customer in the seed data.
  const res = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(token) });
  assert.equal(res.status, 403);
});

test('RE/Manager see the whole book', async () => {
  const token = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/customers`, { headers: authHeaders(token) });
  const customers = await res.json();
  const salesmen = new Set(customers.map((c) => c.assignedSalesmanId));
  assert.ok(salesmen.size > 1, 'RE should see customers across multiple salesmen');
});

test('recording a PTP Scheduled outcome creates a real PTP and closes prior open tasks', async () => {
  const token = await login(app.baseUrl, 'rahul');

  const before1 = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(token) }).then((r) => r.json());
  const openForC1Before = before1.filter((t) => t.customerId === 'C1' && t.status !== 'completed' && t.status !== 'closed');
  assert.ok(openForC1Before.length > 0, 'seed data should have an open task on C1 to supersede');

  const res = await fetch(`${app.baseUrl}/api/customers/C1/record-outcome`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({
      nextAction: 'PTP Scheduled',
      reason: 'Customer committed to pay',
      details: 'Will pay by bank transfer',
      ptpAmountValue: 120000,
      ptpDate: new Date(Date.now() + 3 * 86400000).toISOString(),
      ptpMode: 'Bank Transfer',
    }),
  });
  assert.equal(res.status, 200);
  const detail = await res.json();
  // A PTP that covers only PART of the overdue no longer parks the whole
  // customer — the salesperson keeps working the uncovered remainder (see
  // recoveryReconcileService.reconcileState). C1 owes 400000, PTP is
  // 120000, so 280000 is still actionable.
  assert.equal(detail.currentRecoveryState, 'Action Required');
  assert.equal(detail.actionableAmount, 130000); // 400000 owed - (150000 seed PTP + 120000 new PTP)
  assert.equal(detail.coveredAmount, 270000);
  // A PTP-Scheduled outcome must get its own specific audit label, not a
  // generic "OUTCOME_RECORDED" placeholder — see outcomeAuditLabel() in
  // customerService.js, which mirrors the Dart client's local-mode logic.
  const outcomeEvent = detail.auditHistory.find((e) => e.type === 'Promise To Pay Recorded');
  assert.ok(outcomeEvent, 'expected a specific "Promise To Pay Recorded" audit label, not a generic placeholder');
  // auditHistory must be camelCase like every other domain in the API —
  // a snake_case leak here (occurred_at instead of occurredAt) would
  // silently break any camelCase-only client (e.g. the Flutter app's
  // AuditEvent.fromJson).
  assert.ok(outcomeEvent.occurredAt, 'expected camelCase occurredAt, not snake_case occurred_at');
  assert.equal(outcomeEvent.occurred_at, undefined);

  const ptps = await fetch(`${app.baseUrl}/api/ptps`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.ok(ptps.some((p) => p.customerId === 'C1' && p.amountPromised === 120000));

  const after1 = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(token) }).then((r) => r.json());
  const stillOpenForC1 = after1.filter((t) => t.customerId === 'C1' && t.status !== 'completed' && t.status !== 'closed');
  // The seed tasks are superseded, but a PTP that covers only part of the
  // overdue leaves the single `source='Recovery'` call task open on the
  // uncovered remainder (see customerService.recordOutcome's driveRecoveryTask).
  const superseded = openForC1Before.filter((b) => stillOpenForC1.some((s) => s.id === b.id));
  assert.equal(superseded.length, 0, 'recordOutcome must supersede every prior open task for the customer');
  assert.equal(stillOpenForC1.length, 1, 'the single recovery task is kept for the uncovered remainder');
  assert.equal(stillOpenForC1[0].source, 'Recovery');
  assert.equal(stillOpenForC1[0].type, 'customerCall');
});

test('take-control is RE-only and puts the customer in RE Control', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const forbidden = await fetch(`${app.baseUrl}/api/customers/C2/take-control`, { method: 'POST', headers: authHeaders(salespersonToken) });
  assert.equal(forbidden.status, 403);

  const reToken = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/customers/C2/take-control`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(res.status, 200);
  const detail = await res.json();
  assert.equal(detail.currentRecoveryState, 'RE Control');
});

test('take-control supersedes every prior open task on the customer', async () => {
  // C4, not C1 — an earlier test in this file already superseded C1's
  // seed task via record-outcome, so C1 has nothing left open by now.
  const reToken = await login(app.baseUrl, 'amit.re');
  const before1 = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const openBefore = before1.filter((t) => t.customerId === 'C4' && t.status !== 'completed' && t.status !== 'closed');
  assert.ok(openBefore.length > 0);

  const res = await fetch(`${app.baseUrl}/api/customers/C4/take-control`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(res.status, 200);
  const detail = await res.json();
  assert.ok(detail.auditHistory.some((e) => e.type === 'RE_TAKEN_CONTROL'));

  const after1 = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const stillOpen = after1.filter((t) => t.customerId === 'C4' && t.status !== 'completed' && t.status !== 'closed');
  assert.equal(stillOpen.length, 0, 'take-control must supersede every prior open task, same rule as record-outcome');
});

test('release-control returns the customer to Action Required and is RE-only', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const forbidden = await fetch(`${app.baseUrl}/api/customers/C3/release-control`, { method: 'POST', headers: authHeaders(salespersonToken) });
  assert.equal(forbidden.status, 403);

  const reToken = await login(app.baseUrl, 'amit.re');
  await fetch(`${app.baseUrl}/api/customers/C3/take-control`, { method: 'POST', headers: authHeaders(reToken) });

  const res = await fetch(`${app.baseUrl}/api/customers/C3/release-control`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(res.status, 200);
  const detail = await res.json();
  assert.equal(detail.currentRecoveryState, 'Action Required');
  assert.ok(detail.auditHistory.some((e) => e.type === 'RE_RELEASED_CONTROL'));
});

test('management-instruction creates a real task and supersedes prior open tasks, RE/Manager only', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const forbidden = await fetch(`${app.baseUrl}/api/customers/C2/management-instruction`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ salesmanId: 'rahul', desc: 'Call director', deadline: new Date().toISOString() }),
  });
  assert.equal(forbidden.status, 403);

  const reToken = await login(app.baseUrl, 'amit.re');
  const deadline = new Date(Date.now() + 2 * 86400000).toISOString();
  const res = await fetch(`${app.baseUrl}/api/customers/C2/management-instruction`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ salesmanId: 'rahul', desc: 'Call director', deadline, priority: 'Critical' }),
  });
  assert.equal(res.status, 200);
  const detail = await res.json();
  assert.ok(detail.auditHistory.some((e) => e.type === 'RE_CREATED_INSTRUCTION'));

  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const instruction = tasks.find((t) => t.customerId === 'C2' && t.type === 'managementInstruction' && t.ownerId === 'rahul');
  assert.ok(instruction);
  assert.equal(instruction.reason, 'Call director');
  const stillOpen = tasks.filter((t) => t.customerId === 'C2' && t.status !== 'completed' && t.status !== 'closed');
  assert.equal(stillOpen.length, 1, 'the instruction must be the only open item — every prior open task must be superseded');
});

test('reassign changes the assigned salesperson and preserves audit history, RE/Manager only', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const forbidden = await fetch(`${app.baseUrl}/api/customers/C1/reassign`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ toSalesmanId: 'mahesh', reason: 'x' }),
  });
  assert.equal(forbidden.status, 403);

  const reToken = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/customers/C1/reassign`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ toSalesmanId: 'mahesh', reason: 'Rahul overloaded' }),
  });
  assert.equal(res.status, 200);
  const detail = await res.json();
  assert.equal(detail.assignedSalesmanId, 'mahesh');
  assert.ok(detail.auditHistory.some((e) => e.type === 'RE_CHANGED_OWNER'));
  // Audit history must never be rewritten — earlier entries attributed to
  // the original salesperson must still be there.
  assert.ok(detail.auditHistory.some((e) => e.type === 'SEEDED'));
});

test('repeated No Answer outcomes keep exactly ONE recurring call task; a full day with nothing recorded rolls it into a Physical Visit', async () => {
  const { query } = require('../src/config/db');
  const { sweepNoAnswerCycle } = require('../src/services/missedDeadlineService');
  const token = await login(app.baseUrl, 'rahul');
  const recordNoAnswer = () =>
    fetch(`${app.baseUrl}/api/customers/C3/record-outcome`, {
      method: 'POST',
      headers: authHeaders(token),
      body: JSON.stringify({ nextAction: 'Call Customer', reason: 'No Answer', details: 'Next Call needed' }),
    });
  const tasksFor = async () =>
    (await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(token) }).then((r) => r.json()))
      .filter((t) => t.customerId === 'C3');

  await recordNoAnswer();
  await recordNoAnswer();
  await recordNoAnswer();

  let t = await tasksFor();
  const noAnswerCalls = t.filter((x) => x.type === 'customerCall' && x.source === 'No Answer' && x.status !== 'completed');
  assert.equal(noAnswerCalls.length, 1, '3 No Answers keep exactly one recurring call task, never three');
  assert.equal(t.filter((x) => x.type === 'physicalVisit' && x.status !== 'completed').length, 0, 'no Physical Visit yet — that comes only after a full day');

  // Back-date the recurring task to yesterday, then run the 2-hour cycle.
  await query("UPDATE tasks SET created_at = NOW() - INTERVAL 2 DAY, deadline = NOW() - INTERVAL 2 DAY WHERE id = :id", { id: noAnswerCalls[0].id });
  await sweepNoAnswerCycle();

  t = await tasksFor();
  assert.equal(t.filter((x) => x.type === 'customerCall' && x.source === 'No Answer' && x.status !== 'completed').length, 0, 'the recurring call task is removed');
  assert.equal(t.filter((x) => x.type === 'physicalVisit' && x.reason === 'Non-response threshold reached' && x.status !== 'completed').length, 1, 'a Physical Visit is created after the full day');
});

test('recording a non-No-Answer outcome closes the recurring No Answer call task', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const recordNoAnswer = () =>
    fetch(`${app.baseUrl}/api/customers/C3/record-outcome`, {
      method: 'POST',
      headers: authHeaders(token),
      body: JSON.stringify({ nextAction: 'Call Customer', reason: 'No Answer', details: 'rang out' }),
    });
  const openNoAnswerCalls = async () =>
    (await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(token) }).then((r) => r.json()))
      .filter((t) => t.customerId === 'C3' && t.type === 'customerCall' && t.source === 'No Answer' && t.status !== 'completed').length;

  await recordNoAnswer();
  await recordNoAnswer();
  assert.equal(await openNoAnswerCalls(), 1, 'a No Answer leaves one recurring call task');

  // A different outcome — the salesman actually reached the customer.
  await fetch(`${app.baseUrl}/api/customers/C3/record-outcome`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ nextAction: 'Follow-up', reason: 'Will Confirm', details: 'call back tomorrow' }),
  });
  assert.equal(await openNoAnswerCalls(), 0, 'recording any real outcome supersedes the No Answer call task');
});

test('a No Answer leaves the account actionable so the salesman can record the real outcome when the customer calls back', async () => {
  const token = await login(app.baseUrl, 'mahesh');

  const noAnswer = await fetch(`${app.baseUrl}/api/customers/C5/record-outcome`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ nextAction: 'Call Customer', reason: 'No Answer', details: 'Rang out, will retry' }),
  });
  assert.equal(noAnswer.status, 200);
  const afterNoAnswer = await noAnswer.json();
  assert.notEqual(afterNoAnswer.currentRecoveryState, 'Waiting / Monitoring', 'a No Answer must not park the account');

  // Customer calls back — the salesman records the PTP normally (no lock, no approval).
  const ptp = await fetch(`${app.baseUrl}/api/customers/C5/record-outcome`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({
      nextAction: 'PTP Scheduled',
      reason: 'Customer called back and committed',
      details: 'Will pay by UPI',
      ptpAmountValue: 15000,
      ptpDate: new Date(Date.now() + 2 * 86400000).toISOString(),
      ptpMode: 'UPI',
    }),
  });
  assert.equal(ptp.status, 200);
  const afterPtp = await ptp.json();
  // C5 already carries a seed PTP (P5, 60000) and dispute (D_001, 25000);
  // adding a 15000 PTP means the whole 60000 overdue is covered, so it
  // still parks.
  assert.equal(afterPtp.currentRecoveryState, 'Waiting / Monitoring', 'fully-covered account parks');

  const ptps = await fetch(`${app.baseUrl}/api/ptps`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.ok(ptps.some((p) => p.customerId === 'C5' && p.amountPromised === 15000), 'the callback PTP must have been created');
});

test('GET /api/customers already arrives sorted by real recovery priority — escalation severity first', async () => {
  const token = await login(app.baseUrl, 'amit.re');
  const customers = await fetch(`${app.baseUrl}/api/customers`, { headers: authHeaders(token) }).then((r) => r.json());
  // C4 (Metro Motors) is seeded at L2 — the only escalated customer — so it
  // must be first regardless of any other customer's overdue days/amount.
  assert.equal(customers[0].id, 'C4');
});

test('GET /api/customers/next returns the single highest-priority customer for the caller, server-computed', async () => {
  const token = await login(app.baseUrl, 'mahesh');
  const next = await fetch(`${app.baseUrl}/api/customers/next`, { headers: authHeaders(token) }).then((r) => r.json());
  // Mahesh owns C4 (L2, escalated) and C5 (none) — C4 must win.
  assert.equal(next.id, 'C4');
});

test('GET /api/customers and /api/customers/:id return a real, computed creditHealthScore/Band and hasValidNextAction', async () => {
  const token = await login(app.baseUrl, 'amit.re');
  const detail = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.ok(typeof detail.creditHealthScore === 'number');
  assert.equal(detail.creditHealthBand, 'Critical', 'C4 is 75 days overdue, escalated, with a broken PTP — the worst band');
  assert.equal(typeof detail.hasValidNextAction, 'boolean');
});
