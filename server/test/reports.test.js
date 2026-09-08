const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const { runSnapshot } = require('../src/workers/snapshotWorker');

let app;

before(async () => {
  await resetDb();
  app = await startTestApp();
});

after(async () => {
  await teardownAll(app);
});

test('a salesperson\'s dashboard is scoped to their own portfolio, not the whole book', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/reports/dashboard`, { headers: authHeaders(token) });
  assert.equal(res.status, 200);
  const data = await res.json();
  // Rahul owns C1/C2/C3 (₹400000+₹300000+₹45000 = ₹745000 from seed) — never the full company's ₹1555000.
  assert.equal(data.totalOverdueAmount, 745000);
  assert.equal(data.totalOverdueCustomerCount, 3);
});

test('RE/Management see the real company-wide aggregates, ageing buckets, and PTP overview — genuinely derived, not hand-typed', async () => {
  const token = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/reports/dashboard`, { headers: authHeaders(token) });
  const data = await res.json();
  assert.equal(data.totalOverdueAmount, 1555000);
  assert.equal(data.totalOverdueCustomerCount, 5);
  const ageingSum = Object.values(data.outstandingAgeingBuckets).reduce((s, v) => s + v, 0);
  assert.equal(ageingSum, data.totalOverdueAmount, 'ageing buckets must sum to exactly the total overdue amount');
  assert.equal(data.ptpOverviewStats.givenCount, 5, 'seed has 5 PTPs');
  assert.ok(data.topOverdueCustomers.length > 0);
  assert.equal(data.topOverdueCustomers[0].id, 'C4', 'Metro Motors (₹750000) is the single largest overdue account in the seed');
});

test('a real action that matures a PTP genuinely moves the dashboard numbers on the next fetch', async () => {
  const salesperson = await login(app.baseUrl, 'mahesh');
  const re = await login(app.baseUrl, 'amit.re');

  const before1 = await fetch(`${app.baseUrl}/api/reports/dashboard`, { headers: authHeaders(re) }).then((r) => r.json());

  await fetch(`${app.baseUrl}/api/ptps/P5/mark-outcome`, {
    method: 'POST',
    headers: authHeaders(re),
    body: JSON.stringify({ outcome: 'kept', amountReceived: 60000 }),
  });

  const after1 = await fetch(`${app.baseUrl}/api/reports/dashboard`, { headers: authHeaders(re) }).then((r) => r.json());
  assert.equal(after1.totalOverdueAmount, before1.totalOverdueAmount - 60000);
  assert.ok(after1.totalReceivedAllTime >= before1.totalReceivedAllTime + 60000);
  void salesperson;
});

test('a salesperson cannot see disputes/salesmen roster data folded into another role\'s dashboard view', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/reports/dashboard`, { headers: authHeaders(token) });
  const data = await res.json();
  // A salesperson has no reason to see the company disputes total — the
  // dashboard omits company-wide-only figures for this role rather than
  // leaking them.
  assert.equal(data.totalDisputesCount, 0);
});

test('the trends endpoint returns only real, genuinely-recorded snapshot rows — no fabricated history', async () => {
  const token = await login(app.baseUrl, 'amit.re');
  const before1 = await fetch(`${app.baseUrl}/api/reports/trends`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.equal(before1.length, 0, 'no snapshot has run yet in a freshly-seeded test database');

  await runSnapshot();

  const after1 = await fetch(`${app.baseUrl}/api/reports/trends`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.equal(after1.length, 1, 'exactly one real row for today after the snapshot runs once');
  assert.ok(after1[0].avgRecoveryScore >= 0 && after1[0].avgRecoveryScore <= 100);

  await runSnapshot();
  const after2 = await fetch(`${app.baseUrl}/api/reports/trends`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.equal(after2.length, 1, 'running the snapshot again the same day updates today\'s row rather than duplicating it');
});
