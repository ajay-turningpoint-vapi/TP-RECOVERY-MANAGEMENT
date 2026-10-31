const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const { query } = require('../src/config/db');

// RE lists, 30 Oct rules:
//   "No next step"   = owes money and no outcome has ever been recorded
//   "Not followed up" = an outcome was recorded, the salesman got a task and
//                       it is still not done 5 days after it was created

let app;
let re;
let rahul;
before(async () => {
  await resetDb();
  app = await startTestApp();
  re = await login(app.baseUrl, 'amit.re');
  rahul = await login(app.baseUrl, 'rahul');
});
after(async () => {
  await teardownAll(app);
});

const customer = async (id) => (await fetch(`${app.baseUrl}/api/customers`, { headers: authHeaders(re) }).then((r) => r.json())).find((c) => c.id === id);
const notFollowedUp = async () =>
  (await fetch(`${app.baseUrl}/api/reports/dashboard`, { headers: authHeaders(re) }).then((r) => r.json())).noFollowUpAccounts.map((c) => c.id);

test('a customer with no recorded outcome is "No next step"; the first outcome takes it out', async () => {
  const before1 = await customer('C3');
  assert.equal(before1.hasValidNextAction, false, 'owes money, nothing ever recorded');
  assert.equal(before1.followUpMissedSince, null);

  const res = await fetch(`${app.baseUrl}/api/customers/C3/record-outcome`, {
    method: 'POST',
    headers: authHeaders(rahul),
    body: JSON.stringify({ nextAction: 'Call Customer', reason: 'Customer Refused', details: 'Reason: cash flow' }),
  });
  assert.equal(res.status, 200);
  assert.equal((await customer('C3')).hasValidNextAction, true, 'recorded once — never "No next step" again');
});

test('a salesman task left undone for 5 days after an outcome is "Not followed up"', async () => {
  // A task the salesman got 4 days ago — not yet.
  await query(
    "INSERT INTO tasks (id, type, customer_id, owner_id, deadline, priority, reason, status, source, created_at) VALUES ('T_LATE', 'customerCall', 'C3', 'rahul', NOW() - INTERVAL 4 DAY, 'High', 'Call', 'pending', 'Recovery', NOW() - INTERVAL 4 DAY)"
  );
  assert.ok(!(await notFollowedUp()).includes('C3'), '4 days — not yet');
  assert.equal((await customer('C3')).followUpMissedSince, null);

  await query("UPDATE tasks SET created_at = NOW() - INTERVAL 6 DAY WHERE id = 'T_LATE'");
  assert.ok((await notFollowedUp()).includes('C3'), '6 days undone — listed');
  assert.ok((await customer('C3')).followUpMissedSince, 'flag set on the customer too');

  await query("UPDATE tasks SET status = 'completed', completed_at = NOW() WHERE id = 'T_LATE'");
  assert.ok(!(await notFollowedUp()).includes('C3'), 'done — off the list');
});

const instruct = (id, salesmanId) =>
  fetch(`${app.baseUrl}/api/customers/${id}/management-instruction`, {
    method: 'POST',
    headers: authHeaders(re),
    body: JSON.stringify({ salesmanId, desc: 'Call and get a first outcome', deadline: new Date(Date.now() + 86400000).toISOString(), priority: 'High', taskType: 'customerCall' }),
  });

test('the RE can create a task only for a never-contacted customer', async () => {
  // C3 has a recorded outcome (first test) — its tasks come from that outcome.
  const refused = await instruct('C3', 'rahul');
  assert.equal(refused.status, 400);
  assert.match((await refused.json()).error.message, /never been contacted/);

  // C4: never contacted, only the routine daily automatic call open.
  await query("UPDATE tasks SET status = 'completed' WHERE customer_id = 'C4'");
  await query(
    "INSERT INTO tasks (id, type, customer_id, owner_id, deadline, priority, reason, status, source, is_routine) VALUES ('T_ROUTINE', 'customerCall', 'C4', 'mahesh', NOW() + INTERVAL 6 HOUR, 'Normal', 'Start recovery', 'pending', 'Recovery', 1)"
  );
  // ...and the RE's own "Missed Deadline" reminder (30 Oct: 303 of 332
  // never-contacted customers had one, and it wrongly blocked the RE).
  await query(
    "INSERT INTO tasks (id, type, customer_id, owner_id, deadline, priority, reason, status, source, is_routine) VALUES ('T_MISSED', 'customerCall', 'C4', 'amit-re', NOW() + INTERVAL 2 HOUR, 'High', 'Salesman missed the call', 'pending', 'Missed Deadline', 1)"
  );
  const ok = await instruct('C4', 'mahesh');
  assert.equal(ok.status, 200, 'neither the routine call nor the RE reminder blocks the RE');
  const closed = await query("SELECT id, status, outcome FROM tasks WHERE id IN ('T_ROUTINE', 'T_MISSED') ORDER BY id");
  for (const t of closed) {
    assert.equal(t.status, 'completed', `${t.id} is closed — never two calls`);
    assert.match(t.outcome, /^Superseded/);
  }

  const again = await instruct('C4', 'mahesh');
  assert.equal(again.status, 400, 'one real task at a time');
});
