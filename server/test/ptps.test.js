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

test('a salesperson only sees PTPs for their own customers', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/ptps`, { headers: authHeaders(token) });
  assert.equal(res.status, 200);
  const ptps = await res.json();
  assert.ok(ptps.length > 0);
  // Seed: P1/P2/P3 are on C1/C2/C3, all Rahul's customers.
  assert.ok(ptps.every((p) => ['P1', 'P2', 'P3'].includes(p.id)));
});

test('a salesperson can request a correction on their own PTP', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const newDate = new Date(Date.now() + 10 * 86400000).toISOString();
  const res = await fetch(`${app.baseUrl}/api/ptps/P1/request-correction`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ amount: 175000, date: newDate, reason: 'Customer revised commitment' }),
  });
  assert.equal(res.status, 200);
  const ptp = await res.json();
  assert.equal(ptp.correctionStatus, 'Pending');
  assert.equal(ptp.correctionRequestedAmount, 175000);
  assert.equal(ptp.amountPromised, 150000, 'the original commitment must not change until approved');
});

test('RE approving a correction updates the real PTP and preserves the original in the audit trail', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const newDate = new Date(Date.now() + 12 * 86400000).toISOString();
  await fetch(`${app.baseUrl}/api/ptps/P2/request-correction`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ amount: 120000, date: newDate, reason: 'Partial payment agreed' }),
  });

  const reToken = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/ptps/P2/approve-correction`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(res.status, 200);
  const approved = await res.json();
  assert.equal(approved.correctionStatus, 'Approved');
  assert.equal(approved.amountPromised, 120000, 'approval must apply the requested amount to the real commitment');

  const detail = await fetch(`${app.baseUrl}/api/customers/C2`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.ok(detail.auditHistory.some((e) => e.type === 'RE_APPROVED_PTP_CORRECTION'));
});

test('RE rejecting a correction leaves the original PTP commitment unchanged', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  await fetch(`${app.baseUrl}/api/ptps/P3/request-correction`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ amount: 999999, date: new Date().toISOString(), reason: 'test' }),
  });

  const reToken = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/ptps/P3/reject-correction`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ reason: 'Amount looks implausible, verify with customer first' }),
  });
  assert.equal(res.status, 200);
  const rejected = await res.json();
  assert.equal(rejected.correctionStatus, 'Rejected');
  assert.equal(rejected.amountPromised, 35000, 'a rejected correction must never touch the original committed amount (seed P3)');
});

test('a salesperson cannot approve or reject PTP corrections', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res1 = await fetch(`${app.baseUrl}/api/ptps/P1/approve-correction`, { method: 'POST', headers: authHeaders(token) });
  assert.equal(res1.status, 403);
  const res2 = await fetch(`${app.baseUrl}/api/ptps/P1/reject-correction`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ reason: 'x' }),
  });
  assert.equal(res2.status, 403);
});

test('RE marking a PTP Kept applies the real received amount and reduces the customer\'s totalDue', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const before = await fetch(`${app.baseUrl}/api/customers/C5`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const res = await fetch(`${app.baseUrl}/api/ptps/P5/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'kept', amountReceived: 60000 }),
  });
  assert.equal(res.status, 200);
  const ptp = await res.json();
  assert.equal(ptp.status, 'kept');
  assert.equal(ptp.amountReceived, 60000);

  const after = await fetch(`${app.baseUrl}/api/customers/C5`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(after.totalDue, before.totalDue - 60000, 'a Kept PTP must genuinely reduce financial exposure, not just relabel itself');
  assert.ok(after.auditHistory.some((e) => e.type === 'PTP_KEPT_PAYMENT_APPLIED'));
});

test('RE marking a PTP Partially Kept only reduces totalDue by the real amount actually received', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const before = await fetch(`${app.baseUrl}/api/customers/C2`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const res = await fetch(`${app.baseUrl}/api/ptps/P2/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'partiallyKept', amountReceived: 40000 }),
  });
  assert.equal(res.status, 200);
  const ptp = await res.json();
  assert.equal(ptp.status, 'partiallyKept');

  const after = await fetch(`${app.baseUrl}/api/customers/C2`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(after.totalDue, before.totalDue - 40000, 'only the real ₹40,000 actually received must reduce exposure — not the full ₹1,00,000 promised');
  assert.ok(after.auditHistory.some((e) => e.type === 'PTP_PARTIALLY_KEPT_PAYMENT_APPLIED'));
});

test('an over-payment (received amount larger than totalDue) clamps totalDue/totalOutstanding at zero rather than going negative', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const salespersonToken = await login(app.baseUrl, 'rahul');

  // A fresh PTP, not one of the seed rows other tests in this file depend
  // on (P1 in particular — the escalation-ladder test below relies on it
  // still being scheduled).
  await fetch(`${app.baseUrl}/api/customers/C3/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({
      nextAction: 'PTP Scheduled',
      reason: 'Will pay next week',
      details: 'PTP amount: 999999',
      ptpAmountValue: 999999,
      ptpDate: new Date(Date.now() + 86400000).toISOString(),
      ptpMode: 'UPI',
    }),
  });
  const ptps = await fetch(`${app.baseUrl}/api/ptps`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const freshPtp = ptps.find((p) => p.customerId === 'C3' && p.status === 'scheduled' && p.amountPromised === 999999);

  const before = await fetch(`${app.baseUrl}/api/customers/C3`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.ok(before.totalDue > 0, 'sanity check on seed state');

  const res = await fetch(`${app.baseUrl}/api/ptps/${freshPtp.id}/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'kept', amountReceived: before.totalDue + 500000 }),
  });
  assert.equal(res.status, 200);

  const after = await fetch(`${app.baseUrl}/api/customers/C3`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(after.totalDue, 0, 'totalDue must clamp at zero, never go negative');
  assert.equal(after.totalOutstanding, 0, 'totalOutstanding must clamp at zero, never go negative');
});

test('2 broken PTPs on the same customer reach L2, a 3rd reaches L3 — never auto L4', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const reToken = await login(app.baseUrl, 'amit.re');

  // C1 starts with only P1 (already scheduled from seed) — create 2 more
  // real PTPs on C1 via the real record-outcome flow so there are 3 to break.
  for (let i = 0; i < 2; i++) {
    await fetch(`${app.baseUrl}/api/customers/C1/record-outcome`, {
      method: 'POST',
      headers: authHeaders(salespersonToken),
      body: JSON.stringify({
        nextAction: 'PTP Scheduled',
        reason: 'Will pay next week',
        details: `PTP amount: ${50000 + i}`,
        ptpAmountValue: 50000 + i,
        ptpDate: new Date(Date.now() + 86400000).toISOString(),
        ptpMode: 'UPI',
      }),
    });
  }

  const ptps = await fetch(`${app.baseUrl}/api/ptps`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const c1ScheduledIds = ptps.filter((p) => p.customerId === 'C1' && p.status === 'scheduled').map((p) => p.id);
  assert.equal(c1ScheduledIds.length, 3, 'C1 must have exactly 3 real scheduled PTPs to break in this test');

  // 1st break: not enough yet.
  await fetch(`${app.baseUrl}/api/ptps/${c1ScheduledIds[0]}/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'broken', brokenReason: 'No response' }),
  });
  let c1 = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(c1.escalationLevel, 'none', '1 broken PTP alone must not escalate');

  // 2nd break: reaches L2.
  await fetch(`${app.baseUrl}/api/ptps/${c1ScheduledIds[1]}/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'broken', brokenReason: 'No response' }),
  });
  c1 = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(c1.escalationLevel, 'L2', '2 broken PTPs must reach L2');
  assert.ok(c1.auditHistory.some((e) => e.type === 'ESCALATION_RAISED' && e.actor === 'System'));

  // 3rd break: reaches L3.
  await fetch(`${app.baseUrl}/api/ptps/${c1ScheduledIds[2]}/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'broken', brokenReason: 'No response' }),
  });
  c1 = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(c1.escalationLevel, 'L3', '3 broken PTPs must reach L3');
  assert.notEqual(c1.escalationLevel, 'L4', 'broken PTPs must never auto-escalate to L4 — that stays a human/RE judgment call');
});

test('a PTP can only be reconciled once, and a salesperson cannot mark outcomes', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const salespersonToken = await login(app.baseUrl, 'rahul');

  const alreadyKept = await fetch(`${app.baseUrl}/api/ptps/P5/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'broken' }),
  });
  assert.equal(alreadyKept.status, 400, 'P5 was already marked Kept in an earlier test — reconciling it again must be rejected');

  const forbidden = await fetch(`${app.baseUrl}/api/ptps/P3/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ outcome: 'kept', amountReceived: 100 }),
  });
  assert.equal(forbidden.status, 403);
});
