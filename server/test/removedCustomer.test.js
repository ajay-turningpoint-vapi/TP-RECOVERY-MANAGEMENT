const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const { query } = require('../src/config/db');
const customerRepository = require('../src/repositories/customerRepository');
const notificationRepository = require('../src/repositories/notificationRepository');
const { promoteDuePtps, finalizeDuePtps } = require('../src/services/ptpVerificationService');

// 30 Oct: a customer removed from BUSY at 11:25 still had its PTP marked
// broken by the 12:10 job, and the RE saw it with a bare code and
// "Salesman Unmapped". A customer BUSY no longer has must not reach the RE.

let app;
let re;
before(async () => {
  await resetDb();
  app = await startTestApp();
  re = await login(app.baseUrl, 'amit.re');
});
after(async () => {
  await teardownAll(app);
});

const get = (path) => fetch(`${app.baseUrl}/api${path}`, { headers: authHeaders(re) }).then((r) => r.json());
const removeFromBusy = (id) => query("UPDATE customers SET busy_salesman_code = 999, busy_still_active = 0 WHERE id = :id", { id });

test('a removed customer\'s promise is never checked or broken', async () => {
  // C1 has scheduled PTP P1 — make it due, then remove C1 from BUSY.
  await query("UPDATE ptps SET promise_date = NOW() - INTERVAL 3 DAY WHERE id = 'P1'");
  await removeFromBusy('C1');
  await promoteDuePtps();
  await finalizeDuePtps(async () => []); // BUSY: no receipts at all
  const [p1] = await query("SELECT status FROM ptps WHERE id = 'P1'");
  assert.equal(p1.status, 'scheduled', 'left alone — not promoted, not broken');
});

test('removed from BUSY = removed from RMS: nothing of the customer leaves the server', async () => {
  // C4 has broken PTP P4 + task T3; C3 has kept PTP P3.
  await removeFromBusy('C4');
  await removeFromBusy('C3');
  const ids = (await get('/ptps')).map((p) => p.id);
  assert.ok(!ids.includes('P1'), 'open promise hidden');
  assert.ok(!ids.includes('P4'), 'broken promise hidden');
  assert.ok(!ids.includes('P3'), 'kept promise hidden too — the customer is gone from RMS');
  assert.ok(ids.includes('P2'), 'active customers are unaffected');

  assert.ok(!(await get('/tasks')).some((t) => ['C1', 'C3', 'C4'].includes(t.customerId)), 'no tasks');
  assert.ok(!(await get('/disputes')).some((d) => ['C1', 'C3', 'C4'].includes(d.customerId)), 'no disputes');
  assert.ok(!(await get('/payment-claims')).some((c) => ['C1', 'C3', 'C4'].includes(c.customerId)), 'no payment claims');
  assert.ok(!(await get('/customers')).some((c) => ['C1', 'C3', 'C4'].includes(c.id)), 'not in the customer list');

  const detail = await fetch(`${app.baseUrl}/api/customers/C4`, { headers: authHeaders(re) });
  assert.equal(detail.status, 404, 'customer page is gone');
  const history = await fetch(`${app.baseUrl}/api/customers/C4/audit-history`, { headers: authHeaders(re) });
  assert.equal(history.status, 404, 'history is gone');

  // A salesman never sees it either.
  const mahesh = await login(app.baseUrl, 'mahesh');
  const theirTasks = await fetch(`${app.baseUrl}/api/tasks`, { headers: authHeaders(mahesh) }).then((r) => r.json());
  assert.ok(!theirTasks.some((t) => t.customerId === 'C4'));
});

test('escalations and notifications about a removed customer are hidden; leaving BUSY closes open escalations', async () => {
  await query(
    "INSERT INTO escalation_cases (id, customer_id, level, reason, plan, owner_id, deadline, money_at_risk, is_open) VALUES ('E_RM', 'C5', 'L2', 'x', '', 'amit-re', NOW(), 1000, 1)"
  );
  await notificationRepository.insert({ userId: null, severity: 'warning', title: 'PTP broken', body: 'x', customerId: 'C5' });
  await removeFromBusy('C5');

  assert.ok(!(await get('/escalations')).some((e) => e.customerId === 'C5'));
  const notes = await get('/notifications');
  assert.ok(!notes.items.some((n) => n.customerId === 'C5'));
  assert.equal(notes.unreadCount, notes.items.filter((n) => !n.isRead).length);

  await customerRepository.closeOutRemovedCustomers(['C5']);
  const [esc] = await query("SELECT is_open FROM escalation_cases WHERE id = 'E_RM'");
  assert.equal(Number(esc.is_open), 0);
});
