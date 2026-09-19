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

test('the manual mark-outcome endpoint no longer exists — PTP outcomes are decided only by BUSY verification', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/ptps/P5/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'kept', amountReceived: 60000 }),
  });
  assert.equal(res.status, 404, 'the manual mark-outcome route was removed; a PTP outcome now only comes from ptpVerificationService');
});
