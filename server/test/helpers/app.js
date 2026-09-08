const createApp = require('../../src/app');

/** Boots a real instance of the app on an ephemeral port for one test file. */
async function startTestApp() {
  const app = createApp();
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const port = server.address().port;
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

async function login(baseUrl, username, password = '1234') {
  const res = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  if (res.status !== 200) {
    throw new Error(`login failed for ${username}: ${res.status} ${await res.text()}`);
  }
  const body = await res.json();
  // login now returns {accessToken, refreshToken, user} (see authService.js's
  // refresh-token rework) — was just {token, user}; tests only ever need
  // the access token to authenticate requests.
  return body.accessToken;
}

function authHeaders(token) {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

module.exports = { startTestApp, login, authHeaders };
