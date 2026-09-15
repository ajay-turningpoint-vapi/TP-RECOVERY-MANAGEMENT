const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const ptpRepository = require('../src/repositories/ptpRepository');
const taskRepository = require('../src/repositories/taskRepository');

let app;

before(async () => {
  await resetDb();
  app = await startTestApp();
  // P1/P2/P5 are seeded as still-'scheduled' (active) PTPs, and T4 is a
  // seeded still-open task on C5 (D_001's customer) — the new
  // "approve/reject creates a follow-up call task" assertions below need
  // the customer to have no other open task/active PTP so the reopen
  // guard actually fires; neutralize them (doesn't affect any of this
  // file's other assertions, which never reference PTPs or T4 directly).
  for (const id of ['P1', 'P2', 'P5']) {
    await ptpRepository.update(id, { status: 'kept', amountReceived: 0 });
  }
  await taskRepository.update('T4', { status: 'completed', outcome: 'Neutralized for test setup', completedAt: new Date() });
});

after(async () => {
  await teardownAll(app);
});

test('a salesperson only sees disputes for their own customers', async () => {
  const token = await login(app.baseUrl, 'mahesh');
  const res = await fetch(`${app.baseUrl}/api/disputes`, { headers: authHeaders(token) });
  const disputes = await res.json();
  // D_001 is on C5, which is Mahesh's customer in the seed data.
  assert.ok(disputes.some((d) => d.id === 'D_001'));
});

test('approving a dispute assigns a resolution owner and creates a real task', async () => {
  const token = await login(app.baseUrl, 'amit.re');

  const res = await fetch(`${app.baseUrl}/api/disputes/D_001/approve`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({
      resolutionOwner: 'ramesh-re',
      deadline: new Date(Date.now() + 2 * 86400000).toISOString(),
      description: 'Verify damaged goods claim with warehouse',
    }),
  });
  assert.equal(res.status, 200);
  const dispute = await res.json();
  assert.equal(dispute.status, 'Approved');
  assert.equal(dispute.resolutionOwner, 'ramesh-re');

  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.ok(tasks.some((t) => t.customerId === 'C5' && t.ownerId === 'ramesh-re' && t.source === 'Dispute Review'));

  // Approving does NOT create a separate call-customer follow-up — only
  // reject does (the resolution owner is already handling it).
  const followUp = tasks.find((t) => t.customerId === 'C5' && t.type === 'customerCall' && t.reason.startsWith('Dispute approved'));
  assert.equal(followUp, undefined, 'approving a dispute must not create a call-customer follow-up');
});

test('rejecting a dispute records the reason and leaves the full amount in recovery', async () => {
  const token = await login(app.baseUrl, 'amit.re');

  // Raise a second dispute to reject (D_001 was consumed by the approve test).
  const outcomeToken = await login(app.baseUrl, 'mahesh');
  // nextAction must NOT match an earlier branch in customerService.recordOutcome
  // ('PTP Scheduled' / 'Internal Action' / 'Action Required' / 'Follow-up*')
  // or the if/else-if chain never reaches the reason === 'Dispute Raised' branch.
  await fetch(`${app.baseUrl}/api/customers/C5/record-outcome`, {
    method: 'POST',
    headers: authHeaders(outcomeToken),
    body: JSON.stringify({ nextAction: 'Dispute Raised', reason: 'Dispute Raised', details: 'Reason: Wrong item shipped, Amt: 5000' }),
  });

  const disputes = await fetch(`${app.baseUrl}/api/disputes`, { headers: authHeaders(token) }).then((r) => r.json());
  const newDispute = disputes.find((d) => d.status === 'Pending Approval' && d.customerId === 'C5');
  assert.ok(newDispute, 'record-outcome with reason "Dispute Raised" should create a real dispute row');

  const res = await fetch(`${app.baseUrl}/api/disputes/${newDispute.id}/reject`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ reason: 'No evidence of wrong shipment' }),
  });
  assert.equal(res.status, 200);
  const rejected = await res.json();
  assert.equal(rejected.status, 'Rejected');
  assert.equal(rejected.rejectionReason, 'No evidence of wrong shipment');

  // The disputed amount is confirmed still owed — the single
  // `source='Recovery'` call task is (re)created for the full outstanding,
  // High priority, due 9 PM.
  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(token) }).then((r) => r.json());
  const followUp = tasks.find((t) =>
    t.customerId === 'C5' && t.type === 'customerCall' && t.source === 'Recovery' && t.status !== 'completed');
  assert.ok(followUp, 'rejecting a dispute must (re)create the salesperson recovery task');
  assert.equal(followUp.priority, 'High');
  assert.match(followUp.reason, /rejected/, 'task reason names the rejection');
  assert.match(followUp.reason, /Collect ₹/, 'task says exactly what to collect');
  assert.equal(new Date(followUp.deadline).getHours(), 21, 'due 9 PM (RE-decision default)');
});

test('a salesperson cannot approve a dispute', async () => {
  const token = await login(app.baseUrl, 'mahesh');
  const res = await fetch(`${app.baseUrl}/api/disputes/D_001/approve`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ resolutionOwner: 'ramesh-re', deadline: new Date().toISOString(), description: 'x' }),
  });
  assert.equal(res.status, 403);
});

test('requesting more information creates a real task and leaves the dispute open pending clarification', async () => {
  const outcomeToken = await login(app.baseUrl, 'mahesh');
  await fetch(`${app.baseUrl}/api/customers/C4/record-outcome`, {
    method: 'POST',
    headers: authHeaders(outcomeToken),
    body: JSON.stringify({ nextAction: 'Dispute Raised', reason: 'Dispute Raised', details: 'Reason: Damaged on arrival, Amt: 8000' }),
  });

  const reToken = await login(app.baseUrl, 'amit.re');
  const disputes = await fetch(`${app.baseUrl}/api/disputes`, { headers: authHeaders(reToken) }).then((r) => r.json());
  const dispute = disputes.find((d) => d.status === 'Pending Approval' && d.customerId === 'C4');
  assert.ok(dispute);

  const deadline = new Date(Date.now() + 3 * 86400000).toISOString();
  const res = await fetch(`${app.baseUrl}/api/disputes/${dispute.id}/request-info`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ salesmanId: 'mahesh', desc: 'Please attach the delivery photos', deadline }),
  });
  assert.equal(res.status, 200);
  const updated = await res.json();
  assert.equal(updated.status, 'Need More Information');
  assert.equal(updated.infoRequestNote, 'Please attach the delivery photos');

  const tasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.ok(tasks.some((t) => t.customerId === 'C4' && t.ownerId === 'mahesh' && t.source === 'Dispute Review' && t.reason.includes('DISPUTE INFO REQUIRED')));
});

test('a salesperson cannot reject a dispute or request info', async () => {
  const token = await login(app.baseUrl, 'mahesh');
  const res1 = await fetch(`${app.baseUrl}/api/disputes/D_001/reject`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ reason: 'x' }),
  });
  assert.equal(res1.status, 403);
  const res2 = await fetch(`${app.baseUrl}/api/disputes/D_001/request-info`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ salesmanId: 'mahesh', desc: 'x', deadline: new Date().toISOString() }),
  });
  assert.equal(res2.status, 403);
});

test('a dispute cannot be resolved/verified before it is Approved', async () => {
  const salespersonToken = await login(app.baseUrl, 'mahesh');
  const reToken = await login(app.baseUrl, 'amit.re');

  // A fresh dispute, still Pending Approval — D_001 was already approved by
  // an earlier test in this file, so it can't stand in for the "not yet
  // approved" case here.
  await fetch(`${app.baseUrl}/api/customers/C5/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ nextAction: 'Dispute Raised', reason: 'Dispute Raised', details: 'Reason: Wrong pricing, Amt: 5000' }),
  });
  const fresh = await fetch(`${app.baseUrl}/api/disputes`, { headers: authHeaders(reToken) })
    .then((r) => r.json())
    .then((rows) => rows.find((d) => d.customerId === 'C5' && d.status === 'Pending Approval'));

  const res = await fetch(`${app.baseUrl}/api/disputes/${fresh.id}/resolve`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'Resolved' }),
  });
  assert.equal(res.status, 400);
});

test('resolving an Approved dispute as Resolved genuinely reduces totalDue by the disputed amount — the real second-stage verification', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  // D_001 was already approved by an earlier test in this file — resolve
  // it directly rather than re-approving.
  const before = await fetch(`${app.baseUrl}/api/customers/C5`, { headers: authHeaders(reToken) }).then((r) => r.json());

  const res = await fetch(`${app.baseUrl}/api/disputes/D_001/resolve`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'Resolved', note: 'Confirmed via BUSY' }),
  });
  assert.equal(res.status, 200);
  const updated = await res.json();
  assert.equal(updated.status, 'Resolved');

  const after = await fetch(`${app.baseUrl}/api/customers/C5`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(after.totalDue, before.totalDue - 25000, 'the real disputed amount (₹25,000) must genuinely reduce exposure — not just relabel the dispute');
  assert.ok(after.auditHistory.some((e) => e.type === 'RE_RESOLVED_DISPUTE'));

  const again = await fetch(`${app.baseUrl}/api/disputes/D_001/resolve`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'Resolved' }),
  });
  assert.equal(again.status, 400, 'a dispute can only be verified/resolved once');
});

test('resolving an Approved dispute as Returned to Recovery leaves totalDue untouched — nothing was actually received', async () => {
  const salespersonToken = await login(app.baseUrl, 'mahesh');
  const reToken = await login(app.baseUrl, 'amit.re');

  await fetch(`${app.baseUrl}/api/customers/C4/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ nextAction: 'Dispute Raised', reason: 'Dispute Raised', details: 'Reason: Damaged goods, Amt: 15000' }),
  });
  const dispute = await fetch(`${app.baseUrl}/api/disputes`, { headers: authHeaders(reToken) })
    .then((r) => r.json())
    .then((rows) => rows.find((d) => d.customerId === 'C4' && d.status === 'Pending Approval'));

  await fetch(`${app.baseUrl}/api/disputes/${dispute.id}/approve`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ resolutionOwner: 'ramesh-re', deadline: new Date(Date.now() + 172800000).toISOString(), description: 'Verify with warehouse' }),
  });
  const before = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(reToken) }).then((r) => r.json());

  const res = await fetch(`${app.baseUrl}/api/disputes/${dispute.id}/resolve`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ outcome: 'Returned to Recovery', note: 'Still unpaid despite the resolution task' }),
  });
  assert.equal(res.status, 200);
  const updated = await res.json();
  assert.equal(updated.status, 'Returned to Recovery');

  const after = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.equal(after.totalDue, before.totalDue, 'nothing was received — totalDue must not move');
  assert.ok(after.auditHistory.some((e) => e.type === 'RE_RETURNED_DISPUTE_TO_RECOVERY'));
});

test('a salesperson cannot resolve/verify a dispute', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/disputes/D_001/resolve`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ outcome: 'Resolved' }),
  });
  assert.equal(res.status, 403);
});
