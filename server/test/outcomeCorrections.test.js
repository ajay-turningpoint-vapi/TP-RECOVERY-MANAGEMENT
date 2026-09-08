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

test('a salesperson can request a correction on their own customer, and the original values are read from the server, not the client', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/outcome-corrections/customer/C1`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ requestedOutcome: 'Follow-up', requestedReason: 'Fixed typo', requestNote: 'Wrong reason recorded' }),
  });
  assert.equal(res.status, 200);
  const req = await res.json();
  assert.equal(req.status, 'Pending');
  // C1's real seeded values — never trusted from the client.
  assert.equal(req.originalOutcome, 'CALL CUSTOMER');
  assert.equal(req.originalReason, 'Overdue follow-up');
  assert.equal(req.salesmanId, 'rahul');

  const customer = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.ok(customer.auditHistory.some((e) => e.type === 'SALESPERSON_REQUESTED_OUTCOME_CORRECTION'));
});

test('a salesperson cannot request a correction on another salesperson\'s customer', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/outcome-corrections/customer/C4`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ requestedOutcome: 'Follow-up', requestedReason: 'x', requestNote: 'x' }),
  });
  assert.equal(res.status, 403);
});

test('RE approving a request genuinely rewrites the customer\'s recorded outcome, and it can only be decided once', async () => {
  const salespersonToken = await login(app.baseUrl, 'mahesh');
  const reToken = await login(app.baseUrl, 'amit.re');

  const created = await fetch(`${app.baseUrl}/api/outcome-corrections/customer/C4`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ requestedOutcome: 'Follow-up', requestedReason: 'Customer asked to call back tomorrow', requestNote: 'Recorded wrong reason during the call' }),
  }).then((r) => r.json());

  const res = await fetch(`${app.baseUrl}/api/outcome-corrections/${created.id}/approve`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(res.status, 200);
  const approved = await res.json();
  assert.equal(approved.status, 'Approved');

  const customer = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(customer.primaryNextAction, 'Follow-up');
  assert.equal(customer.reasonForAction, 'Customer asked to call back tomorrow');
  assert.ok(customer.auditHistory.some((e) => e.type === 'RE_APPROVED_OUTCOME_CORRECTION'));

  const again = await fetch(`${app.baseUrl}/api/outcome-corrections/${created.id}/approve`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(again.status, 400, 'a decided request cannot be decided again');
});

test('RE rejecting a request leaves the customer\'s recorded outcome unchanged and records the reason', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const reToken = await login(app.baseUrl, 'amit.re');

  const before = await fetch(`${app.baseUrl}/api/customers/C2`, { headers: authHeaders(reToken) }).then((r) => r.json());

  const created = await fetch(`${app.baseUrl}/api/outcome-corrections/customer/C2`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ requestedOutcome: 'Follow-up', requestedReason: 'x', requestNote: 'Trying to change it' }),
  }).then((r) => r.json());

  const res = await fetch(`${app.baseUrl}/api/outcome-corrections/${created.id}/reject`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ reason: 'Original outcome was accurate' }),
  });
  assert.equal(res.status, 200);
  const rejected = await res.json();
  assert.equal(rejected.status, 'Rejected');
  assert.equal(rejected.rejectionReason, 'Original outcome was accurate');

  const after = await fetch(`${app.baseUrl}/api/customers/C2`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(after.primaryNextAction, before.primaryNextAction);
  assert.equal(after.reasonForAction, before.reasonForAction);
});

test('a salesperson only sees their own requests; RE/Management see all', async () => {
  const rahulToken = await login(app.baseUrl, 'rahul');
  const reToken = await login(app.baseUrl, 'amit.re');

  const rahulList = await fetch(`${app.baseUrl}/api/outcome-corrections`, { headers: authHeaders(rahulToken) }).then((r) => r.json());
  assert.ok(rahulList.every((r) => r.salesmanId === 'rahul'));

  const reList = await fetch(`${app.baseUrl}/api/outcome-corrections`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const salesmenInList = new Set(reList.map((r) => r.salesmanId));
  assert.ok(salesmenInList.size > 1, 'RE must see requests across more than one salesperson');
});

test('a salesperson cannot approve or reject outcome correction requests', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const reToken = await login(app.baseUrl, 'amit.re');
  const created = await fetch(`${app.baseUrl}/api/outcome-corrections/customer/C1`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ requestedOutcome: 'Follow-up', requestedReason: 'x', requestNote: 'x' }),
  }).then((r) => r.json());

  const approveAttempt = await fetch(`${app.baseUrl}/api/outcome-corrections/${created.id}/approve`, { method: 'POST', headers: authHeaders(salespersonToken) });
  assert.equal(approveAttempt.status, 403);
  const rejectAttempt = await fetch(`${app.baseUrl}/api/outcome-corrections/${created.id}/reject`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ reason: 'x' }),
  });
  assert.equal(rejectAttempt.status, 403);
  void reToken;
});
