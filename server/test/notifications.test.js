const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const { createNotificationWorker } = require('../src/workers/notificationWorker');
const { notificationQueue } = require('../src/queues/notificationQueue');

let app;
let worker;

before(async () => {
  await resetDb();
  app = await startTestApp();
  // Drain any notification jobs left in the shared (bull-test-prefixed) Redis
  // by earlier test files — otherwise this file's fresh worker would replay
  // that backlog and waitForJob() could resolve on a stale job.
  await notificationQueue.obliterate({ force: true });
  // A real worker, scoped to the test-only BullMQ key prefix (env.redis.prefix
  // = 'bull-test' under NODE_ENV=test) — this can never collide with the
  // real dev/pm2 worker sharing the same Redis instance.
  worker = createNotificationWorker();
});

after(async () => {
  await worker.close();
  await teardownAll(app);
});

function waitForJob(targetWorker, predicate, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      targetWorker.off('completed', onCompleted);
      reject(new Error('Timed out waiting for BullMQ job to complete'));
    }, timeoutMs);
    function onCompleted(job) {
      if (predicate(job)) {
        clearTimeout(timer);
        targetWorker.off('completed', onCompleted);
        resolve(job);
      }
    }
    targetWorker.on('completed', onCompleted);
  });
}

test('raising an escalation queues a real notification that the worker delivers end-to-end', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');

  const jobDone = waitForJob(worker, (job) => job.data.userId === 'mahesh' && job.data.customerId === 'C4');

  const escalateRes = await fetch(`${app.baseUrl}/api/escalations/customer/C4`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ level: 'L3', reason: 'Broken PTP, no response', ownerId: 'mahesh' }),
  });
  assert.equal(escalateRes.status, 200);

  await jobDone;

  const salespersonToken = await login(app.baseUrl, 'mahesh');
  const res = await fetch(`${app.baseUrl}/api/notifications`, { headers: authHeaders(salespersonToken) });
  const body = await res.json();
  assert.ok(body.items.some((n) => n.customerId === 'C4' && n.severity === 'critical'));
  assert.ok(body.unreadCount >= 1);
});

test('marking a notification read only affects that user, never a broadcast for everyone', async () => {
  const token = await login(app.baseUrl, 'mahesh');
  const listBefore = await fetch(`${app.baseUrl}/api/notifications`, { headers: authHeaders(token) }).then((r) => r.json());
  const own = listBefore.items.find((n) => n.userId === 'mahesh');
  assert.ok(own, 'expected a per-user notification from the previous test');

  const readRes = await fetch(`${app.baseUrl}/api/notifications/${own.id}/read`, { method: 'POST', headers: authHeaders(token) });
  assert.equal(readRes.status, 200);
  assert.equal((await readRes.json()).isRead, true);
});

test('a user cannot mark another user\'s notification as read', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const jobDone = waitForJob(worker, (job) => job.data.userId === 'rahul');
  await fetch(`${app.baseUrl}/api/escalations/customer/C1`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ level: 'L1', reason: 'test', ownerId: 'rahul' }),
  });
  await jobDone;

  const rahulToken = await login(app.baseUrl, 'rahul');
  const list = await fetch(`${app.baseUrl}/api/notifications`, { headers: authHeaders(rahulToken) }).then((r) => r.json());
  const target = list.items.find((n) => n.userId === 'rahul');
  assert.ok(target);

  const maheshToken = await login(app.baseUrl, 'mahesh');
  const res = await fetch(`${app.baseUrl}/api/notifications/${target.id}/read`, { method: 'POST', headers: authHeaders(maheshToken) });
  assert.equal(res.status, 403);
});
