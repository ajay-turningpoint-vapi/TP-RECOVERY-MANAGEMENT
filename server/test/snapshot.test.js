const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const { runSnapshot } = require('../src/workers/snapshotWorker');
const customerRepository = require('../src/repositories/customerRepository');
const taskRepository = require('../src/repositories/taskRepository');
const notificationRepository = require('../src/repositories/notificationRepository');

before(async () => {
  await resetDb();
});

after(async () => {
  await teardownAll();
});

test('the daily snapshot reopens recovery only for customers with money due and nothing else open', async () => {
  // Seed state: C1 has an active PTP (P1) — must NOT be reopened.
  // C3 (PQR Stores, ₹45,000 due) has no task and its only PTP is "kept" —
  // MUST be reopened by the snapshot.
  const result = await runSnapshot();
  assert.ok(result.checked >= 1);
  assert.ok(result.reopened >= 1);

  const c1Tasks = await taskRepository.findByCustomer('C1');
  const c1OpenFromSnapshot = c1Tasks.filter((t) => t.source === 'Daily Snapshot');
  assert.equal(c1OpenFromSnapshot.length, 0, 'C1 has an active PTP (P1) — the snapshot must not touch it');

  const c3Tasks = await taskRepository.findByCustomer('C3');
  const c3FromSnapshot = c3Tasks.filter((t) => t.source === 'Daily Snapshot');
  assert.equal(c3FromSnapshot.length, 1, 'C3 has money due and nothing open — the snapshot should reopen it exactly once');
});

test('running the snapshot twice in a row does not create duplicate follow-up tasks', async () => {
  await runSnapshot();
  const c3Tasks = await taskRepository.findByCustomer('C3');
  const fromSnapshot = c3Tasks.filter((t) => t.source === 'Daily Snapshot');
  assert.equal(fromSnapshot.length, 1, 'the guard checks for existing open work first — a second run must be a no-op for an already-reopened customer');
});

test('the snapshot leaves a broadcast notification summarizing the run', async () => {
  const notifications = await notificationRepository.findForUser('rahul');
  assert.ok(notifications.some((n) => n.title === '5 PM control snapshot complete' && n.userId === null));
});

test('customers with no money due are never touched by the snapshot', async () => {
  const allCustomers = await customerRepository.findAll();
  const zeroDue = allCustomers.filter((c) => c.totalDue <= 0);
  // Seed data has no zero-due customers, but this documents/enforces the
  // filter's intent even if seed data changes later.
  for (const c of zeroDue) {
    const tasks = await taskRepository.findByCustomer(c.id);
    assert.ok(!tasks.some((t) => t.source === 'Daily Snapshot'));
  }
});
