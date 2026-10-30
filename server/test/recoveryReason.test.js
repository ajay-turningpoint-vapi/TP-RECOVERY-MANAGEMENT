const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const customerRepository = require('../src/repositories/customerRepository');
const taskRepository = require('../src/repositories/taskRepository');
const { driveRecoveryTask } = require('../src/services/recoveryTaskService');

// SURESH SUTHAR.(R), 30 Oct: the PTP broke and a new call task opened, but
// the customer's reasonForAction still said "PTP of ₹50,000 …", so the
// web / Customer 360 showed the old step. The stored reason must always
// match the recovery task the salesperson actually holds.

before(async () => {
  await resetDb();
});

after(async () => {
  await teardownAll();
});

const openRecoveryTask = async (id) =>
  (await taskRepository.findByCustomer(id)).find((t) => t.source === 'Recovery' && !['completed', 'closed'].includes(t.status));

test('a new recovery task rewrites the customer reasonForAction', async () => {
  await customerRepository.update('C3', { reasonForAction: 'PTP of ₹50000.0 via Phone Call. Contact: PQR' });

  await driveRecoveryTask('C3', { headline: 'Call PQR Stores — promise broken, nothing received.', priority: 'High' });

  const task = await openRecoveryTask('C3');
  assert.ok(task, 'a recovery task should be open');
  const customer = await customerRepository.findById('C3');
  assert.equal(customer.reasonForAction, task.reason);
  assert.match(customer.reasonForAction, /promise broken/);
  assert.doesNotMatch(customer.reasonForAction, /PTP of ₹50000/);
});

test('the daily refresh of that task keeps reasonForAction in step', async () => {
  await driveRecoveryTask('C3', { refreshOnly: true });
  const task = await openRecoveryTask('C3');
  const customer = await customerRepository.findById('C3');
  assert.equal(customer.reasonForAction, task.reason);
});
