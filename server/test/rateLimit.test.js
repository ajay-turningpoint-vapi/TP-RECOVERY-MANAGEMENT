const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp } = require('./helpers/app');
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

test('the login endpoint advertises its rate limit via standard headers', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'rahul', password: 'wrong' }),
  });
  assert.ok(res.headers.get('ratelimit-limit'), 'expected a RateLimit-Limit header on the login route');
});

test('exceeding the login limit returns 429 with the centralized error shape', async () => {
  // loginLimiter caps at 20 requests / 15 min per IP — deliberately exceed it.
  let lastRes;
  for (let i = 0; i < 21; i += 1) {
    lastRes = await fetch(`${app.baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'rahul', password: 'wrong' }),
    });
    if (lastRes.status === 429) break;
  }
  assert.equal(lastRes.status, 429);
  const body = await lastRes.json();
  assert.equal(body.error.code, 'TOO_MANY_REQUESTS');
  assert.ok(body.requestId);
});
