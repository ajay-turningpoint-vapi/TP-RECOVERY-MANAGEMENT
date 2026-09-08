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

test('a salesperson cannot raise an escalation', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/escalations/customer/C1`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ level: 'L1', reason: 'nope' }),
  });
  assert.equal(res.status, 403);
});

test('raising an escalation bumps the customer\'s escalationLevel', async () => {
  const token = await login(app.baseUrl, 'amit.re');

  const before1 = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.equal(before1.escalationLevel, 'none');

  const res = await fetch(`${app.baseUrl}/api/escalations/customer/C1`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ level: 'L2', reason: 'Customer unresponsive', ownerId: 'rahul', moneyAtRisk: 150000 }),
  });
  assert.equal(res.status, 200);
  const escalation = await res.json();
  assert.equal(escalation.level, 'L2');
  assert.equal(escalation.isOpen, true);

  const after1 = await fetch(`${app.baseUrl}/api/customers/C1`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.equal(after1.escalationLevel, 'L2');
});

test('a less severe escalation never downgrades an already-more-severe level', async () => {
  const token = await login(app.baseUrl, 'amit.re');

  await fetch(`${app.baseUrl}/api/escalations/customer/C2`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ level: 'L3', reason: 'first, severe' }),
  });
  await fetch(`${app.baseUrl}/api/escalations/customer/C2`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ level: 'L1', reason: 'second, less severe' }),
  });

  const detail = await fetch(`${app.baseUrl}/api/customers/C2`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.equal(detail.escalationLevel, 'L3', 'the more severe L3 must not be overwritten by a later, less severe L1');
});

test('resolving the last open escalation resets the customer to none; an earlier one leaves it alone', async () => {
  const token = await login(app.baseUrl, 'amit.re');

  const raised = await fetch(`${app.baseUrl}/api/escalations/customer/C3`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ level: 'L1', reason: 'only escalation on C3' }),
  }).then((r) => r.json());

  const resolved = await fetch(`${app.baseUrl}/api/escalations/${raised.id}/resolve`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ note: 'customer responded' }),
  });
  assert.equal(resolved.status, 200);

  const detail = await fetch(`${app.baseUrl}/api/customers/C3`, { headers: authHeaders(token) }).then((r) => r.json());
  assert.equal(detail.escalationLevel, 'none');
});
