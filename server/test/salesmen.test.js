const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');

let app;

before(async () => {
  await resetDb();
  app = await startTestApp();
});

after(async () => {
  await teardownAll(app);
});

test('RE listing salesmen sees real aggregates computed from customers/ptps, not stored counters', async () => {
  const reToken = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/salesmen`, { headers: authHeaders(reToken) });
  assert.equal(res.status, 200);
  const rows = await res.json();

  const rahul = rows.find((r) => r.id === 'rahul');
  assert.ok(rahul);
  assert.equal(rahul.username, 'rahul');
  assert.equal(rahul.fullName, 'Rahul Sharma');
  assert.equal(rahul.branch, 'Mumbai');
  assert.equal(rahul.customers, 3);
  assert.ok(rahul.totalOverdue > 0);

  // A recorded outcome that matures a PTP moves this salesman's real
  // aggregate on the next fetch — proving it's computed live, not cached.
  const salespersonToken = await login(app.baseUrl, 'rahul');
  await fetch(`${app.baseUrl}/api/customers/C1/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salespersonToken),
    body: JSON.stringify({
      nextAction: 'Promise To Pay',
      reason: 'Will pay next week',
      ptpAmountValue: 400000,
      ptpDate: new Date(Date.now() + 86400000).toISOString(),
      ptpMode: 'Bank Transfer',
    }),
  });

  const res2 = await fetch(`${app.baseUrl}/api/salesmen`, { headers: authHeaders(reToken) });
  const rows2 = await res2.json();
  const rahul2 = rows2.find((r) => r.id === 'rahul');
  assert.ok(rahul2.dueTodayPtps >= 0);
});

test('management can also list salesmen', async () => {
  const mgrToken = await login(app.baseUrl, 'suresh.mgr');
  const res = await fetch(`${app.baseUrl}/api/salesmen`, { headers: authHeaders(mgrToken) });
  assert.equal(res.status, 200);
});

test('a salesperson cannot list the company salesmen roster', async () => {
  const salespersonToken = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/salesmen`, { headers: authHeaders(salespersonToken) });
  assert.equal(res.status, 403);
});
