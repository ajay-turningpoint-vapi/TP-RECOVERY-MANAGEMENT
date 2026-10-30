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
