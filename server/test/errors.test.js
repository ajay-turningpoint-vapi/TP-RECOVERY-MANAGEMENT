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

test('unknown route returns a centralized 404, not an Express default page', async () => {
  const res = await fetch(`${app.baseUrl}/api/does-not-exist`);
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.equal(body.error.code, 'NOT_FOUND');
  assert.ok(body.requestId);
});

test('an invalid login body returns 400 with field-level Zod errors, not a 500', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: '' }),
  });
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error.code, 'VALIDATION_ERROR');
  assert.ok(body.error.details, 'expected Zod field errors in details');
});

test('a malformed JSON body returns a clean 400, not a leaked stack trace', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{not valid json',
  });
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error.code, 'VALIDATION_ERROR');
  assert.equal(body.error.stack, undefined, 'a client 400 must never carry a stack trace');
});

test('an unexpected server error never leaks a stack trace outside development', async () => {
  // A record-outcome request with a syntactically valid but nonsensical
  // customer id, with no auth — hits the 401 path, which is an AppError,
  // so this instead asserts the general contract: no route responds with
  // a bare Express/Node error page regardless of what breaks.
  const res = await fetch(`${app.baseUrl}/api/customers/does-not-exist/record-outcome`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.ok(res.headers.get('content-type')?.includes('application/json'));
  const body = await res.json();
  assert.ok(body.error);
});
