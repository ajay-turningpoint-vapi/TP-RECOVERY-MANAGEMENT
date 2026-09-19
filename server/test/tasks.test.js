const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const taskRepository = require('../src/repositories/taskRepository');

let app;

async function tasksFor(token) {
  return fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(token) }).then((r) => r.json());
}

before(async () => {
  await resetDb();
  app = await startTestApp();
});

after(async () => {
  await teardownAll(app);
});

test('completing a task with a PTP covering only part of the balance keeps a recovery task for the uncovered remainder', async () => {
  const token = await login(app.baseUrl, 'rahul');
  // Seed: C1 owes 400000, has task T1 and an active (scheduled) PTP P1 for
  // 150000 — so 250000 is still the salesperson's to recover.
  const before1 = await tasksFor(token);
  const t1 = before1.find((t) => t.id === 'T1');
  assert.equal(t1.status, 'pending');

  // T1 is a physicalVisit task — completing it now requires real photo
  // evidence the visit happened (attachmentPath).
  const res = await fetch(`${app.baseUrl}/api/tasks/T1/complete`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ attachmentPath: '/uploads/test-visit-photo.jpg' }),
  });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).status, 'completed');

  const after1 = await tasksFor(token);
  const openForC1 = after1.filter((t) => t.customerId === 'C1' && t.status !== 'completed' && t.status !== 'closed');
  // A partial PTP no longer parks the whole customer — driveRecoveryTask
  // keeps the single `source='Recovery'` call task on the uncovered slice.
  assert.equal(openForC1.length, 1);
  assert.equal(openForC1[0].source, 'Recovery');
  assert.equal(openForC1[0].type, 'customerCall');
});

test('completing the last open task with money still due and no active PTP reopens recovery', async () => {
  const token = await login(app.baseUrl, 'rahul');

  // C3 (PQR Stores) has no seed task and its only PTP (P3) is already
  // "kept", not active — create one via record-outcome, then complete it.
  // (Uses 'Customer Refused', not 'Follow-up' — a Will Confirm no longer
  // creates any task immediately, only once its scheduled time passes via
  // followUpQueue; 'Customer Refused' still retargets the recovery task
  // right away, same as before, and exercises the same reopen path below.)
  const outcomeRes = await fetch(`${app.baseUrl}/api/customers/C3/record-outcome`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ nextAction: 'Call Customer', reason: 'Customer Refused', details: 'Refused to commit to a date' }),
  });
  assert.equal(outcomeRes.status, 200);

  const midTasks = await tasksFor(token);
  const newTask = midTasks.find((t) => t.customerId === 'C3' && t.status !== 'completed');
  assert.ok(newTask, 'record-outcome with Customer Refused should have created an open task for C3');

  const completeRes = await fetch(`${app.baseUrl}/api/tasks/${newTask.id}/complete`, { method: 'POST', headers: authHeaders(token) });
  assert.equal(completeRes.status, 200);

  const afterTasks = await tasksFor(token);
  const reopened = afterTasks.find((t) => t.customerId === 'C3' && t.status !== 'completed' && t.source === 'Recovery');
  assert.ok(reopened, 'C3 still has ₹45,000 due with nothing else open — driveRecoveryTask should have created the recovery call task');

  const detail = await fetch(`${app.baseUrl}/api/customers/C3`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.ok(detail.auditHistory.some((e) => e.type === 'RECOVERY_TASK_CREATED'));
});

test('completing a Physical Visit task without a photo is rejected — the server, not just the UI, enforces it', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const visitId = await taskRepository.insert({
    type: 'physicalVisit',
    customerId: 'C1',
    ownerId: 'rahul',
    deadline: new Date(Date.now() - 3600000),
    priority: 'High',
    reason: 'Test physical visit — no photo yet',
  });

  const noPhoto = await fetch(`${app.baseUrl}/api/tasks/${visitId}/complete`, { method: 'POST', headers: authHeaders(token) });
  assert.equal(noPhoto.status, 400, 'a Physical Visit must not complete without photo evidence');

  const withPhoto = await fetch(`${app.baseUrl}/api/tasks/${visitId}/complete`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ attachmentPath: '/uploads/second-test-visit-photo.jpg' }),
  });
  assert.equal(withPhoto.status, 200, 'the same visit must complete once a photo is provided');

  const detail = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(token) }).then((r) => r.json());
  const visitAudit = detail.auditHistory.find((e) => e.type === 'TASK_COMPLETED' && e.description.includes('physicalVisit') && e.attachmentPath);
  assert.ok(visitAudit, 'the visit photo must be preserved in the customer\'s history, not just the task');
});

test('a salesperson cannot complete another salesperson\'s task', async () => {
  const token = await login(app.baseUrl, 'rahul');
  // T3 belongs to Mahesh (owner) on customer C4.
  const res = await fetch(`${app.baseUrl}/api/tasks/T3/complete`, { method: 'POST', headers: authHeaders(token) });
  assert.equal(res.status, 403);
});

test('a salesperson can request an extension, and RE can approve it', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const newDeadline = new Date(Date.now() + 3 * 86400000).toISOString();

  const reqRes = await fetch(`${app.baseUrl}/api/tasks/T2/request-extension`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ reason: 'Customer traveling', deadline: newDeadline, priority: 'High' }),
  });
  assert.equal(reqRes.status, 200);
  const pending = await reqRes.json();
  assert.equal(pending.approvalStatus, 'Pending');

  const reToken = await login(app.baseUrl, 'amit.re');
  const approveRes = await fetch(`${app.baseUrl}/api/tasks/T2/approve-edit`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(approveRes.status, 200);
  const approved = await approveRes.json();
  assert.equal(approved.approvalStatus, 'Approved');
  assert.equal(Math.floor(new Date(approved.deadline).getTime() / 1000), Math.floor(new Date(newDeadline).getTime() / 1000));
});

test('RE can reject an extension request, leaving the original deadline unchanged', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const original = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(salespersonToken) }).then((r) => r.json());
  const t1 = original.find((t) => t.id === 'T1');

  await fetch(`${app.baseUrl}/api/tasks/T1/request-extension`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({ reason: 'Need more time', deadline: new Date(Date.now() + 5 * 86400000).toISOString() }),
  });

  const reToken = await login(app.baseUrl, 'amit.re');
  const rejectRes = await fetch(`${app.baseUrl}/api/tasks/T1/reject-edit`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(rejectRes.status, 200);
  const rejected = await rejectRes.json();
  assert.equal(rejected.approvalStatus, 'Rejected');
  assert.equal(new Date(rejected.deadline).toISOString(), new Date(t1.deadline).toISOString(), 'original deadline must stand unchanged after rejection');
});

test('a salesperson cannot request an extension on another salesperson\'s task', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/tasks/T3/request-extension`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ reason: 'x', deadline: new Date().toISOString() }),
  });
  assert.equal(res.status, 403);
});

test('RE can reassign a task to a different owner', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/tasks/T1/reassign`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ newOwnerId: 'mahesh', reason: 'Rahul overloaded' }),
  });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).ownerId, 'mahesh');
});

test('RE can directly reschedule a task without an approval round-trip (no self-approval loop)', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const newDeadline = new Date(Date.now() + 7 * 86400000).toISOString();
  // T4, untouched by earlier tests in this file — T1/T2 accumulate state
  // (completed/approved/rejected/reassigned) across the tests above.
  const res = await fetch(`${app.baseUrl}/api/tasks/T4/reschedule`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ reason: 'Customer requested later visit', newDeadline }),
  });
  assert.equal(res.status, 200);
  const task = await res.json();
  // MariaDB's DATETIME column truncates sub-second precision, so compare
  // to the second, not the exact millisecond.
  assert.equal(Math.floor(new Date(task.deadline).getTime() / 1000), Math.floor(new Date(newDeadline).getTime() / 1000));
  assert.equal(task.approvalStatus, null, 'direct reschedule must not create a Pending approval state');

  const detail = await fetch(`${app.baseUrl}/api/customers/${task.customerId}`, { headers: authHeaders(reToken) }).then((r) => r.json());
  assert.ok(detail.auditHistory.some((e) => e.type === 'RE_RESCHEDULED_TASK'));
});

test('a salesperson cannot reschedule or reassign tasks', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res1 = await fetch(`${app.baseUrl}/api/tasks/T1/reschedule`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ reason: 'x', newDeadline: new Date().toISOString() }),
  });
  assert.equal(res1.status, 403);
  const res2 = await fetch(`${app.baseUrl}/api/tasks/T1/reassign`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ newOwnerId: 'mahesh', reason: 'x' }),
  });
  assert.equal(res2.status, 403);
});

test('RE can mark a completed physical visit as reviewed', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  // T1 (type physicalVisit) was completed by the first test in this file.
  const res = await fetch(`${app.baseUrl}/api/tasks/T1/review`, { method: 'POST', headers: authHeaders(reToken) });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).reviewedByRE, true);
});

test('a salesperson cannot mark a task reviewed', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/tasks/T1/review`, { method: 'POST', headers: authHeaders(token) });
  assert.equal(res.status, 403);
});
