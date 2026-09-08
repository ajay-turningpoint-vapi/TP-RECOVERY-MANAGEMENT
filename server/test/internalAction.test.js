const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const ptpRepository = require('../src/repositories/ptpRepository');

let app;

before(async () => {
  await resetDb();
  app = await startTestApp();
  // P1/P2/P5 are seeded as still-'scheduled' (active) PTPs — the
  // approve/reject "creates a follow-up call task" assertions below need
  // the customer to have no other active PTP so the reopen guard actually
  // fires; neutralize them to a terminal state.
  for (const id of ['P1', 'P2', 'P5']) {
    await ptpRepository.update(id, { status: 'kept', amountReceived: 0 });
  }
});

after(async () => {
  await teardownAll(app);
});

/** Records an Internal Action outcome for the given customer, returns the RE task it created. */
async function raiseInternalAction(customerId, salespersonToken, reToken, details) {
  const res = await fetch(`${app.baseUrl}/api/customers/${customerId}/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ nextAction: 'Internal Action', reason: 'Internal Task', details }),
  });
  assert.equal(res.status, 200);

  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const task = tasks.find((t) => t.customerId === customerId && t.type === 'financialTeamFollowUp' && t.status === 'pending');
  assert.ok(task, 'record-outcome with Internal Action should create a real financialTeamFollowUp task for RE');
  return task;
}

test('RE approving an Internal Action closes the RE task and creates a call-customer follow-up for the salesperson', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const reToken = await login(app.baseUrl, 'amit.re');
  const task = await raiseInternalAction('C1', salespersonToken, reToken, 'Ledger correction needed before recovery can continue');

  const res = await fetch(`${app.baseUrl}/api/tasks/${task.id}/approve-internal-action`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ note: 'Ledger corrected in BUSY' }),
  });
  assert.equal(res.status, 200);
  const updated = await res.json();
  assert.equal(updated.status, 'completed');
  assert.ok(updated.outcome && updated.outcome.startsWith('Approved:'));

  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const followUp = tasks.find((t) => t.customerId === 'C1' && t.ownerId === 'rahul' && t.type === 'customerCall' && t.reason === 'Internal action approved');
  assert.ok(followUp, 'approving must create a call-customer follow-up for the salesperson');
  assert.equal(followUp.priority, 'Normal');
  assert.ok(followUp.note && followUp.note.includes('approved'));

  const customer = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(customer.currentRecoveryState, 'Action Required');
  assert.equal(customer.primaryNextAction, 'CALL CUSTOMER');
});

test('RE rejecting an Internal Action closes the RE task and creates a call-customer follow-up for the salesperson', async () => {
  const salespersonToken = await login(app.baseUrl, 'mahesh');
  const reToken = await login(app.baseUrl, 'amit.re');
  const task = await raiseInternalAction('C4', salespersonToken, reToken, 'Requesting a document that does not actually exist');

  const res = await fetch(`${app.baseUrl}/api/tasks/${task.id}/reject-internal-action`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ reason: 'No such document required — invalid request' }),
  });
  assert.equal(res.status, 200);
  const updated = await res.json();
  assert.equal(updated.status, 'completed');
  assert.ok(updated.outcome && updated.outcome.startsWith('Rejected:'));

  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const followUp = tasks.find((t) => t.customerId === 'C4' && t.ownerId === 'mahesh' && t.type === 'customerCall' && t.reason === 'Internal action rejected');
  assert.ok(followUp, 'rejecting must create a call-customer follow-up for the salesperson');
  assert.ok(followUp.note && followUp.note.includes('rejected'));
});

test('an Internal Action cannot be decided twice', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const reToken = await login(app.baseUrl, 'amit.re');
  const task = await raiseInternalAction('C2', salespersonToken, reToken, 'Verify GST details');

  const first = await fetch(`${app.baseUrl}/api/tasks/${task.id}/approve-internal-action`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ note: 'Verified' }),
  });
  assert.equal(first.status, 200);

  const second = await fetch(`${app.baseUrl}/api/tasks/${task.id}/approve-internal-action`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ note: 'Verified again' }),
  });
  assert.equal(second.status, 400, 'an already-decided Internal Action must not be decidable again');
});

test('a salesperson cannot approve or reject an Internal Action', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const reToken = await login(app.baseUrl, 'amit.re');
  const task = await raiseInternalAction('C3', salespersonToken, reToken, 'Needs finance sign-off');

  const res1 = await fetch(`${app.baseUrl}/api/tasks/${task.id}/approve-internal-action`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ note: 'x' }),
  });
  assert.equal(res1.status, 403);

  const res2 = await fetch(`${app.baseUrl}/api/tasks/${task.id}/reject-internal-action`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ reason: 'x' }),
  });
  assert.equal(res2.status, 403);
});
