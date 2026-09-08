const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const ptpRepository = require('../src/repositories/ptpRepository');

let app;

async function createClaimForC1(salespersonToken) {
  const res = await fetch(`${app.baseUrl}/api/customers/C1/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ nextAction: 'Verification Pending', reason: 'Payment Already Made', details: 'Amount: ₹20000' }),
  });
  assert.equal(res.status, 200);
}

before(async () => {
  await resetDb();
  app = await startTestApp();
  // P1/P2/P5 are seeded as still-'scheduled' (active) PTPs — the new
  // "verify creates a follow-up call task" assertions below need the
  // customer to have no other active PTP so the reopen guard actually
  // fires; neutralize them to a terminal state (doesn't affect any of
  // this file's other assertions, which never reference PTPs).
  for (const id of ['P1', 'P2', 'P5']) {
    await ptpRepository.update(id, { status: 'kept', amountReceived: 0 });
  }
});

after(async () => {
  await teardownAll(app);
});

test('a salesperson only sees payment claims for their own customers', async () => {
  const token = await login(app.baseUrl, 'rahul');
  await createClaimForC1(token);

  const res = await fetch(`${app.baseUrl}/api/payment-claims`, { headers: authHeaders(token) });
  assert.equal(res.status, 200);
  const claims = await res.json();
  assert.ok(claims.length > 0);
  // C1/C2/C3 are Rahul's customers in the seed data.
  assert.ok(claims.every((c) => ['C1', 'C2', 'C3'].includes(c.customerId)));
});

test('RE verifying a claim as successful genuinely reduces the customer\'s real outstanding balance', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const before = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(salespersonToken) }).then((r) => r.json());
  const dueBefore = before.totalDue;

  const reToken = await login(app.baseUrl, 'amit.re');
  const claims = await fetch(`${app.baseUrl}/api/payment-claims`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const claim = claims.find((c) => c.customerId === 'C1' && c.status === 'Awaiting Verification');
  assert.ok(claim, 'record-outcome with "Payment Already Made" should have created a real Awaiting Verification claim');

  const res = await fetch(`${app.baseUrl}/api/payment-claims/${claim.id}/verify`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ success: true }),
  });
  assert.equal(res.status, 200);
  const verified = await res.json();
  assert.equal(verified.status, 'Verified');

  const after = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(after.totalDue, dueBefore - claim.amount, 'a Verified claim must genuinely reduce totalDue, not just flip a status label');
  assert.ok(after.auditHistory.some((e) => e.type === 'PAYMENT_CLAIM_VERIFIED'));
});

test('RE marking a claim Failed returns the customer to active recovery without touching totalDue', async () => {
  const salespersonToken = await login(app.baseUrl, 'mahesh');
  const res1 = await fetch(`${app.baseUrl}/api/customers/C4/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ nextAction: 'Verification Pending', reason: 'Payment Already Made', details: 'Amount: ₹15000' }),
  });
  assert.equal(res1.status, 200);

  const reToken = await login(app.baseUrl, 'amit.re');
  const before = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(reToken) }).then((r) => r.json());

  const claims = await fetch(`${app.baseUrl}/api/payment-claims`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const claim = claims.find((c) => c.customerId === 'C4' && c.status === 'Awaiting Verification');
  assert.ok(claim);

  const res = await fetch(`${app.baseUrl}/api/payment-claims/${claim.id}/verify`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ success: false }),
  });
  assert.equal(res.status, 200);
  const failed = await res.json();
  assert.equal(failed.status, 'Failed');

  const after = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(after.totalDue, before.totalDue, 'a Failed claim must never change totalDue');
  assert.ok(after.auditHistory.some((e) => e.type === 'PAYMENT_CLAIM_FAILED'));
});

test('RE verifying a claim as successful creates a call-customer follow-up task with a note for the salesperson', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const res1 = await fetch(`${app.baseUrl}/api/customers/C2/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ nextAction: 'Verification Pending', reason: 'Payment Already Made', details: 'Amount: ₹5000' }),
  });
  assert.equal(res1.status, 200);

  const reToken = await login(app.baseUrl, 'amit.re');
  const claims = await fetch(`${app.baseUrl}/api/payment-claims`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const claim = claims.find((c) => c.customerId === 'C2' && c.status === 'Awaiting Verification');
  assert.ok(claim);

  const res = await fetch(`${app.baseUrl}/api/payment-claims/${claim.id}/verify`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ success: true }),
  });
  assert.equal(res.status, 200);

  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const followUp = tasks.find((t) => t.customerId === 'C2' && t.source === 'Payment Claim Review');
  assert.ok(followUp, 'a follow-up call task must be created after verifying the claim');
  assert.equal(followUp.type, 'customerCall');
  assert.equal(followUp.priority, 'Normal');
  assert.equal(followUp.ownerId, 'rahul');
  assert.ok(followUp.note && followUp.note.includes('verified'), 'task must carry a real note describing the decision');
});

test('RE marking a claim Failed creates a high-priority follow-up call task', async () => {
  const salespersonToken = await login(app.baseUrl, 'mahesh');
  const res1 = await fetch(`${app.baseUrl}/api/customers/C5/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ nextAction: 'Verification Pending', reason: 'Payment Already Made', details: 'Amount: ₹3000' }),
  });
  assert.equal(res1.status, 200);

  const reToken = await login(app.baseUrl, 'amit.re');
  const claims = await fetch(`${app.baseUrl}/api/payment-claims`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const claim = claims.find((c) => c.customerId === 'C5' && c.status === 'Awaiting Verification');
  assert.ok(claim);

  const res = await fetch(`${app.baseUrl}/api/payment-claims/${claim.id}/verify`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ success: false }),
  });
  assert.equal(res.status, 200);

  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const followUp = tasks.find((t) => t.customerId === 'C5' && t.source === 'Payment Claim Review');
  assert.ok(followUp, 'a follow-up call task must be created after rejecting the claim');
  assert.equal(followUp.priority, 'High');
  assert.ok(followUp.note && followUp.note.includes('rejected'));
});

test('a salesperson cannot verify a payment claim', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const claims = await fetch(`${app.baseUrl}/api/payment-claims`, { headers: authHeaders(salespersonToken) }).then((r) => r.json());
  const claim = claims[0];
  const res = await fetch(`${app.baseUrl}/api/payment-claims/${claim.id}/verify`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ success: true }),
  });
  assert.equal(res.status, 403);
});
