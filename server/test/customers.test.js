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
  assert.equal(detail.currentRecoveryState, 'Waiting / Monitoring');
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
  assert.equal(stillOpenForC1.length, 0, 'recordOutcome must supersede every prior open task for the customer');
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

test('repeated No Answer outcomes create a real Physical Visit task at the configured threshold (2), and the counter re-arms after each trigger', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const recordNoAnswer = () =>
    fetch(`${app.baseUrl}/api/customers/C3/record-outcome`, {
      method: 'POST',
      headers: authHeaders(token),
      body: JSON.stringify({ nextAction: 'Call Customer', reason: 'No Answer', details: 'Next Call needed' }),
    });
  const countPhysicalVisits = async () => {
    const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(token) }).then((r) => r.json());
    return tasks.filter((t) => t.customerId === 'C3' && t.type === 'physicalVisit' && t.reason === 'Non-response threshold reached').length;
  };

  await recordNoAnswer();
  assert.equal(await countPhysicalVisits(), 0, 'a single No Answer must not yet trigger a Physical Visit (threshold is 2)');

  await recordNoAnswer();
  assert.equal(await countPhysicalVisits(), 1, 'the 2nd consecutive No Answer must trigger a real Physical Visit task');

  await recordNoAnswer();
  assert.equal(await countPhysicalVisits(), 1, 'the counter resets after triggering — a 3rd call alone must not create a 2nd Physical Visit yet');

  await recordNoAnswer();
  assert.equal(await countPhysicalVisits(), 2, 'the 4th call brings the reset counter to 2 again — the threshold must re-arm and fire a genuine second Physical Visit');
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
  assert.equal(afterPtp.currentRecoveryState, 'Waiting / Monitoring', 'a PTP Scheduled outcome still parks the account');

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
