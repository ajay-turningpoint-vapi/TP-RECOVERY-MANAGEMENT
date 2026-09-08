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

test('login with correct demo credentials returns a token pair and user shape', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'rahul', password: '1234' }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(body.accessToken);
  assert.ok(body.refreshToken);
  assert.equal(body.user.username, 'rahul');
  assert.equal(body.user.role, 'SALESPERSON');
});

test('login with wrong password is rejected, not silently accepted', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'rahul', password: 'wrong-password' }),
  });
  assert.equal(res.status, 401);
});

test('login with unknown username is rejected', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'nobody', password: '1234' }),
  });
  assert.equal(res.status, 401);
});

test('GET /api/auth/me with a valid token returns the caller', async () => {
  const token = await login(app.baseUrl, 'amit.re');
  const res = await fetch(`${app.baseUrl}/api/auth/me`, { headers: authHeaders(token) });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.username, 'amit.re');
  assert.equal(body.role, 'RECOVERY_EXECUTIVE');
});

test('a protected route with no token is rejected', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/me`);
  assert.equal(res.status, 401);
});

test('a protected route with a garbage token is rejected, not treated as unauthenticated', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/me`, { headers: { Authorization: 'Bearer not-a-real-jwt' } });
  assert.equal(res.status, 401);
});

test('refresh exchanges a valid refresh token for a new pair and rotates it (single-use)', async () => {
  const loginRes = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'mahesh', password: '1234' }),
  });
  const { refreshToken } = await loginRes.json();

  const refreshRes = await fetch(`${app.baseUrl}/api/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  });
  assert.equal(refreshRes.status, 200);
  const refreshed = await refreshRes.json();
  assert.ok(refreshed.accessToken);
  assert.ok(refreshed.refreshToken);
  assert.notEqual(refreshed.refreshToken, refreshToken, 'refresh must rotate to a new token, not reuse the old one');

  // The old refresh token was single-use — replaying it must now fail.
  const reuseRes = await fetch(`${app.baseUrl}/api/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  });
  assert.equal(reuseRes.status, 401);
});

test('logout revokes the refresh token — a subsequent refresh with it fails', async () => {
  const loginRes = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'amit.re', password: '1234' }),
  });
  const { refreshToken } = await loginRes.json();

  const logoutRes = await fetch(`${app.baseUrl}/api/auth/logout`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  });
  assert.equal(logoutRes.status, 204);

  const refreshRes = await fetch(`${app.baseUrl}/api/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken }),
  });
  assert.equal(refreshRes.status, 401);
});

test('change-password rejects a too-short new password', async () => {
  const token = await login(app.baseUrl, 'rahul');
  const res = await fetch(`${app.baseUrl}/api/auth/change-password`, {
    method: 'POST',
    headers: authHeaders(token),
    body: JSON.stringify({ newPassword: 'short' }),
  });
  assert.equal(res.status, 400);
});

test('change-password with no token is rejected', async () => {
  const res = await fetch(`${app.baseUrl}/api/auth/change-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ newPassword: 'BrandNew@2026' }),
  });
  assert.equal(res.status, 401);
});

test('change-password updates the password, invalidates old sessions, and keeps this one alive', async () => {
  // A dedicated account so this test's password change doesn't disturb others.
  const loginRes = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'mahesh', password: '1234' }),
  });
  const { accessToken, refreshToken: oldRefresh } = await loginRes.json();

  const changeRes = await fetch(`${app.baseUrl}/api/auth/change-password`, {
    method: 'POST',
    headers: authHeaders(accessToken),
    body: JSON.stringify({ newPassword: 'Mahesh@2026!' }),
  });
  assert.equal(changeRes.status, 200);
  const changed = await changeRes.json();
  assert.ok(changed.accessToken);
  assert.ok(changed.refreshToken);
  assert.notEqual(changed.refreshToken, oldRefresh);

  // Old refresh token is dead (all sessions revoked on password change).
  const oldRefreshRes = await fetch(`${app.baseUrl}/api/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken: oldRefresh }),
  });
  assert.equal(oldRefreshRes.status, 401);

  // The freshly issued session works.
  const meRes = await fetch(`${app.baseUrl}/api/auth/me`, { headers: authHeaders(changed.accessToken) });
  assert.equal(meRes.status, 200);

  // Old password no longer logs in; new one does.
  const oldPw = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'mahesh', password: '1234' }),
  });
  assert.equal(oldPw.status, 401);

  const newPw = await fetch(`${app.baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'mahesh', password: 'Mahesh@2026!' }),
  });
  assert.equal(newPw.status, 200);
});
