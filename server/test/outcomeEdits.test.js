const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const { query } = require('../src/config/db');
const { createNotificationWorker } = require('../src/workers/notificationWorker');
const { notificationQueue } = require('../src/queues/notificationQueue');

let app;
let notifWorker;

before(async () => {
  await resetDb();
  app = await startTestApp();
  // Drain any backlog left by earlier test files sharing this Redis prefix
  // (see notifications.test.js's identical comment) so waitForJob() below
  // can't resolve on a stale job from a different test file.
  await notificationQueue.obliterate({ force: true });
  notifWorker = createNotificationWorker();
});

after(async () => {
  await notifWorker.close();
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

/** Records a PTP outcome on a customer and returns the newly created ptp row. */
async function recordPtp(token, customerId, { amount, dateIso, mode }) {
  const before = await query('SELECT id FROM ptps WHERE customer_id = :customerId', { customerId });
  const seen = new Set(before.map((r) => r.id));
  const res = await fetch(`${app.baseUrl}/api/customers/${customerId}/record-outcome`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({
      nextAction: 'PTP Scheduled',
      reason: 'Customer promised payment',
      details: `PTP of ₹${amount} via ${mode}. Contact: Owner`,
      ptpAmountValue: amount,
      ptpDate: dateIso,
      ptpMode: mode,
    }),
  });
  assert.equal(res.status, 200, 'record-outcome should succeed');
  const after = await query('SELECT * FROM ptps WHERE customer_id = :customerId', { customerId });
  const fresh = after.find((r) => !seen.has(r.id));
  assert.ok(fresh, 'a new scheduled PTP row should exist');
  return fresh;
}

test('salesperson can request a PTP edit on their own customer; original values come from the server', async () => {
  const token = await login(app.baseUrl, 'mahesh');
  const ptp = await recordPtp(token, 'C4', { amount: 5000, dateIso: '2026-10-01T00:00:00.000Z', mode: 'Phone Call' });

  const res = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({
      outcomeKind: 'PTP',
      artifactId: ptp.id,
      requestedPayload: { amount: 7500, promiseDate: '2026-10-05T00:00:00.000Z', paymentMode: 'WhatsApp' },
      editReason: 'Entered the wrong amount and date on the call',
    }),
  });
  assert.equal(res.status, 200);
  const req = await res.json();
  assert.equal(req.status, 'Pending');
  assert.equal(req.outcomeKind, 'PTP');
  assert.equal(Number(req.originalPayload.amount), 5000);
  assert.equal(req.requestedPayload.paymentMode, 'WhatsApp');

  // Nothing applied yet.
  const stillOld = await query('SELECT amount_promised, payment_mode FROM ptps WHERE id = :id', { id: ptp.id });
  assert.equal(Number(stillOld[0].amount_promised), 5000);
  assert.equal(stillOld[0].payment_mode, 'Phone Call');

  const customer = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.ok(customer.auditHistory.some((e) => e.type === 'SALESPERSON_REQUESTED_OUTCOME_EDIT'));
});

test('salesperson cannot request an edit on another salesperson\'s customer', async () => {
  const mahesh = await login(app.baseUrl, 'mahesh');
  const ptp = await recordPtp(mahesh, 'C4', { amount: 1000, dateIso: '2026-10-02T00:00:00.000Z', mode: 'Phone Call' });

  const rahul = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(rahul),
    body: JSON.stringify({
      outcomeKind: 'PTP',
      artifactId: ptp.id,
      requestedPayload: { amount: 2000, promiseDate: '2026-10-06T00:00:00.000Z', paymentMode: 'Phone Call' },
      editReason: 'x',
    }),
  });
  assert.equal(res.status, 403);
});

test('RE approval applies the edited PTP values in place, and it can only be decided once', async () => {
  const sales = await login(app.baseUrl, 'mahesh');
  const re = await login(app.baseUrl, 'amit.re');
  const ptp = await recordPtp(sales, 'C4', { amount: 4000, dateIso: '2026-10-03T00:00:00.000Z', mode: 'Phone Call' });

  const created = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(sales),
    body: JSON.stringify({
      outcomeKind: 'PTP',
      artifactId: ptp.id,
      requestedPayload: { amount: 9000, promiseDate: '2026-10-09T00:00:00.000Z', paymentMode: 'WhatsApp' },
      editReason: 'Customer corrected the amount over WhatsApp',
    }),
  }).then((r) => r.json());

  const res = await fetch(`${app.baseUrl}/api/outcome-edits/${created.id}/approve`, {
    method: 'POST',
    headers: authHeaders(re),
  });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).status, 'Approved');

  const row = await query('SELECT amount_promised, payment_mode, DATE(promise_date) AS d FROM ptps WHERE id = :id', {
    id: ptp.id,
  });
  assert.equal(Number(row[0].amount_promised), 9000);
  assert.equal(row[0].payment_mode, 'WhatsApp');
  assert.equal(String(row[0].d), '2026-10-09');

  const customer = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(re) }).then((r) => r.json());
  assert.ok(customer.auditHistory.some((e) => e.type === 'RE_APPROVED_OUTCOME_EDIT'));

  const again = await fetch(`${app.baseUrl}/api/outcome-edits/${created.id}/approve`, {
    method: 'POST',
    headers: authHeaders(re),
  });
  assert.equal(again.status, 400);
});

test('RE rejection leaves the PTP untouched', async () => {
  const sales = await login(app.baseUrl, 'mahesh');
  const re = await login(app.baseUrl, 'amit.re');
  const ptp = await recordPtp(sales, 'C4', { amount: 3000, dateIso: '2026-10-04T00:00:00.000Z', mode: 'Phone Call' });

  const created = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(sales),
    body: JSON.stringify({
      outcomeKind: 'PTP',
      artifactId: ptp.id,
      requestedPayload: { amount: 999999, promiseDate: '2026-12-01T00:00:00.000Z', paymentMode: 'WhatsApp' },
      editReason: 'trying it on',
    }),
  }).then((r) => r.json());

  const res = await fetch(`${app.baseUrl}/api/outcome-edits/${created.id}/reject`, {
    method: 'POST',
    headers: authHeaders(re),
    body: JSON.stringify({ reason: 'Original PTP was correct' }),
  });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).status, 'Rejected');

  const row = await query('SELECT amount_promised, payment_mode, status FROM ptps WHERE id = :id', { id: ptp.id });
  assert.equal(Number(row[0].amount_promised), 3000);
  assert.equal(row[0].payment_mode, 'Phone Call');
  assert.equal(row[0].status, 'scheduled', 'rejection must leave the original schedule completely untouched');
});

test('approving a PTP edit resets status to scheduled — even mid-verification — so the new schedule runs its own fresh cycle', async () => {
  const sales = await login(app.baseUrl, 'mahesh');
  const re = await login(app.baseUrl, 'amit.re');
  const ptp = await recordPtp(sales, 'C4', { amount: 5000, dateIso: '2026-10-05T00:00:00.000Z', mode: 'Phone Call' });

  // Simulate the PTP already being mid-verification (due date arrived, still
  // in its 1-day grace) when the salesperson requests the edit.
  await query("UPDATE ptps SET status = 'pendingVerification' WHERE id = :id", { id: ptp.id });

  const created = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(sales),
    body: JSON.stringify({
      outcomeKind: 'PTP',
      artifactId: ptp.id,
      requestedPayload: { amount: 7000, promiseDate: '2026-11-01T00:00:00.000Z', paymentMode: 'UPI' },
      editReason: 'Customer asked to push the date out',
    }),
  }).then((r) => r.json());
  assert.equal(created.outcomeKind, 'PTP');

  const res = await fetch(`${app.baseUrl}/api/outcome-edits/${created.id}/approve`, {
    method: 'POST',
    headers: authHeaders(re),
  });
  assert.equal(res.status, 200);

  const row = await query('SELECT amount_promised, status, DATE(promise_date) AS d FROM ptps WHERE id = :id', { id: ptp.id });
  assert.equal(Number(row[0].amount_promised), 7000);
  assert.equal(row[0].status, 'scheduled', 'an approved edit must restart the schedule fresh, not leave it stuck mid-verification against the old date');
  assert.equal(String(row[0].d), '2026-11-01');
});

test('approve and reject both notify the requesting salesperson', async () => {
  const sales = await login(app.baseUrl, 'mahesh');
  const re = await login(app.baseUrl, 'amit.re');

  const ptp1 = await recordPtp(sales, 'C4', { amount: 1000, dateIso: '2026-10-06T00:00:00.000Z', mode: 'Phone Call' });
  const req1 = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(sales),
    body: JSON.stringify({
      outcomeKind: 'PTP',
      artifactId: ptp1.id,
      requestedPayload: { amount: 1500, promiseDate: '2026-10-06T00:00:00.000Z', paymentMode: 'Phone Call' },
      editReason: 'Small correction',
    }),
  }).then((r) => r.json());
  const approveNotified = waitForJob(notifWorker, (job) => job.data.userId === 'mahesh' && /approved/i.test(job.data.title));
  await fetch(`${app.baseUrl}/api/outcome-edits/${req1.id}/approve`, { method: 'POST', headers: authHeaders(re) });
  await approveNotified;

  const ptp2 = await recordPtp(sales, 'C4', { amount: 2000, dateIso: '2026-10-07T00:00:00.000Z', mode: 'Phone Call' });
  const req2 = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(sales),
    body: JSON.stringify({
      outcomeKind: 'PTP',
      artifactId: ptp2.id,
      requestedPayload: { amount: 2500, promiseDate: '2026-10-07T00:00:00.000Z', paymentMode: 'Phone Call' },
      editReason: 'Another correction',
    }),
  }).then((r) => r.json());
  const rejectNotified = waitForJob(notifWorker, (job) => job.data.userId === 'mahesh' && /rejected/i.test(job.data.title));
  await fetch(`${app.baseUrl}/api/outcome-edits/${req2.id}/reject`, {
    method: 'POST',
    headers: authHeaders(re),
    body: JSON.stringify({ reason: 'Not needed' }),
  });
  await rejectNotified;

  const { items: notifications } = await fetch(`${app.baseUrl}/api/notifications`, { headers: authHeaders(sales) }).then((r) => r.json());
  assert.ok(notifications.some((n) => /approved/i.test(n.title)), 'the salesperson must be notified of the approval');
  assert.ok(notifications.some((n) => /rejected/i.test(n.title)), 'the salesperson must be notified of the rejection');
});

test('a second pending edit for the same PTP is refused', async () => {
  const sales = await login(app.baseUrl, 'mahesh');
  const ptp = await recordPtp(sales, 'C4', { amount: 2500, dateIso: '2026-10-07T00:00:00.000Z', mode: 'Phone Call' });
  const body = {
    outcomeKind: 'PTP',
    artifactId: ptp.id,
    requestedPayload: { amount: 2600, promiseDate: '2026-10-08T00:00:00.000Z', paymentMode: 'Phone Call' },
    editReason: 'tweak',
  };
  const first = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(sales),
    body: JSON.stringify(body),
  });
  assert.equal(first.status, 200);
  const second = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(sales),
    body: JSON.stringify(body),
  });
  assert.equal(second.status, 400);
});

test('a salesperson cannot approve or reject; list is scoped per salesperson', async () => {
  const sales = await login(app.baseUrl, 'mahesh');
  const re = await login(app.baseUrl, 'amit.re');
  const ptp = await recordPtp(sales, 'C4', { amount: 1200, dateIso: '2026-10-10T00:00:00.000Z', mode: 'Phone Call' });
  const created = await fetch(`${app.baseUrl}/api/outcome-edits/customer/C4`, {
    method: 'POST',
    headers: authHeaders(sales),
    body: JSON.stringify({
      outcomeKind: 'PTP',
      artifactId: ptp.id,
      requestedPayload: { amount: 1300, promiseDate: '2026-10-11T00:00:00.000Z', paymentMode: 'Phone Call' },
      editReason: 'x',
    }),
  }).then((r) => r.json());

  const approveAttempt = await fetch(`${app.baseUrl}/api/outcome-edits/${created.id}/approve`, {
    method: 'POST',
    headers: authHeaders(sales),
  });
  assert.equal(approveAttempt.status, 403);

  const mine = await fetch(`${app.baseUrl}/api/outcome-edits`, { headers: authHeaders(sales) }).then((r) => r.json());
  assert.ok(mine.every((r) => r.salesmanId === 'mahesh'));

  const all = await fetch(`${app.baseUrl}/api/outcome-edits`, { headers: authHeaders(re) }).then((r) => r.json());
  assert.ok(all.length >= mine.length);
});
