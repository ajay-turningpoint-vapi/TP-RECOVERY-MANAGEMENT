const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp } = require('./helpers/app');
const { teardownAll } = require('./helpers/teardown');

let app;

before(async () => {
  app = await startTestApp();
});

after(async () => {
  await teardownAll(app);
});

test('GET /health is up with no DB dependency', async () => {
  const res = await fetch(`${app.baseUrl}/health`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'ok');
  assert.equal(typeof body.uptimeSeconds, 'number');
});

test('GET /health/ready confirms a real database connection', async () => {
  const res = await fetch(`${app.baseUrl}/health/ready`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'ok');
  assert.equal(body.database, 'connected');
});

test('every response carries an X-Request-Id header', async () => {
  const res = await fetch(`${app.baseUrl}/health`);
  assert.ok(res.headers.get('x-request-id'));
});
