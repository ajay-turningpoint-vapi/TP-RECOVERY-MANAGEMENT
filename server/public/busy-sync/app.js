const TOKEN_KEY = 'busySyncAdminToken';

const IDLE_POLL_MS = 10000;
const RUNNING_POLL_MS = 1200;

let pollTimer = null;
let lastSeenRunId = null; // used to detect "a run just finished" and toast the outcome

const $ = (id) => document.getElementById(id);

function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

function setToken(token) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

async function api(path, options = {}) {
  const res = await fetch(`/api/busy-sync${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${getToken()}`,
      ...(options.headers || {}),
    },
  });
  if (res.status === 401) {
    setToken(null);
    showLogin();
    throw new Error('Session expired — please sign in again.');
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(body.message || `Request failed (${res.status})`);
  }
  return body;
}

// ---------------------------------------------------------------------
// Toasts — transient confirmations/errors
// ---------------------------------------------------------------------

function toast(type, message) {
  const container = $('toast-container');
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = message;
  container.appendChild(el);
  setTimeout(() => el.remove(), 6000);
}

// ---------------------------------------------------------------------
// View switching
// ---------------------------------------------------------------------

function showLogin() {
  stopPolling();
  $('dashboard-view').hidden = true;
  $('login-view').hidden = false;
}

function showDashboard() {
  $('login-view').hidden = true;
  $('dashboard-view').hidden = false;
  lastSeenRunId = null;
  refreshRuns();
  scheduleNextPoll(0);
}

function scheduleNextPoll(delay) {
  stopPolling();
  pollTimer = setTimeout(async () => {
    const stillRunning = await refreshStatus();
    scheduleNextPoll(stillRunning ? RUNNING_POLL_MS : IDLE_POLL_MS);
  }, delay);
}

function stopPolling() {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = null;
}

// ---------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------

function fmtDate(v) {
  if (!v) return '—';
  const d = new Date(v);
  return d.toLocaleString();
}

function fmtDuration(startedAt, finishedAt) {
  if (!startedAt || !finishedAt) return '';
  const ms = new Date(finishedAt).getTime() - new Date(startedAt).getTime();
  return `${(ms / 1000).toFixed(1)}s`;
}

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

const PHASE_LABEL = {
  connecting: 'Connecting to BUSY ERP…',
  fetching: 'Fetching customer report from BUSY…',
  writing: 'Writing to MariaDB (upsert + sweep)…',
};

// ---------------------------------------------------------------------
// Alert banner — persistent while something needs attention
// ---------------------------------------------------------------------

function renderAlertBanner(status) {
  const banner = $('alert-banner');
  const issues = [];
  let severity = 'warn';

  if (!status.connectivity.mssqlConnected) {
    issues.push(`BUSY ERP unreachable${status.connectivity.mssqlLastError ? ': ' + status.connectivity.mssqlLastError : ''}`);
    severity = 'bad';
  }
  if (!status.connectivity.mariaDbHealthy) {
    issues.push('MariaDB unreachable');
    severity = 'bad';
  }
  if (!status.isRunning && status.lastRun?.status === 'failed') {
    issues.push(`Last sync run failed: ${status.lastRun.errorMessage || 'unknown error'}`);
  }

  if (issues.length === 0) {
    banner.hidden = true;
    return;
  }

  banner.hidden = false;
  banner.className = `alert-banner ${severity}`;
  banner.innerHTML = `<span class="dot"></span><span>${issues.map(escapeHtml).join(' &nbsp;·&nbsp; ')}</span>`;
}

// ---------------------------------------------------------------------
// Status + progress
// ---------------------------------------------------------------------

async function refreshStatus() {
  let status;
  try {
    status = await api('/sync/status');
  } catch (err) {
    $('refresh-indicator').textContent = `Error: ${err.message}`;
    return false;
  }

  $('refresh-indicator').textContent = `Updated ${new Date().toLocaleTimeString()}`;
  renderAlertBanner(status);

  const stateEl = $('sync-state');
  if (status.isRunning) {
    stateEl.textContent = 'Running';
    stateEl.className = 'card-value warn';
  } else if (status.lastRun?.status === 'failed') {
    stateEl.textContent = 'Last run failed';
    stateEl.className = 'card-value bad';
  } else if (status.lastRun?.status === 'success') {
    stateEl.textContent = 'Healthy';
    stateEl.className = 'card-value good';
  } else {
    stateEl.textContent = 'No runs yet';
    stateEl.className = 'card-value';
  }

  $('total-customers').textContent = status.totalCustomers.toLocaleString();
  $('last-run').textContent = status.lastRun ? fmtDate(status.lastRun.startedAt) : 'Never';

  const connEl = $('connectivity');
  const mssqlOk = status.connectivity.mssqlConnected;
  const mariaOk = status.connectivity.mariaDbHealthy;
  connEl.textContent = `BUSY: ${mssqlOk ? 'OK' : 'DOWN'} · MariaDB: ${mariaOk ? 'OK' : 'DOWN'}`;
  connEl.className = 'card-value ' + (mssqlOk && mariaOk ? 'good' : 'bad');

  const progressPanel = $('progress-panel');
  const triggerBtn = $('trigger-btn');
  if (status.isRunning) {
    progressPanel.hidden = false;
    triggerBtn.disabled = true;
    const phase = status.progress?.phase;
    $('progress-label').textContent = PHASE_LABEL[phase] || 'Sync in progress…';
    $('progress-detail').textContent =
      status.progress?.rowsFetched != null ? `${status.progress.rowsFetched} rows fetched` : '';
  } else {
    progressPanel.hidden = true;
    triggerBtn.disabled = false;
  }

  // First status poll after login just establishes the baseline — don't
  // toast on it, only on a run that *finishes* while we're watching.
  if (lastSeenRunId === null) {
    lastSeenRunId = status.lastRun?.id ?? -1;
  } else if (!status.isRunning && status.lastRun && status.lastRun.id !== lastSeenRunId) {
    lastSeenRunId = status.lastRun.id;
    refreshRuns();
    if (status.lastRun.status === 'success') {
      toast(
        'success',
        `Sync #${status.lastRun.id} completed — fetched ${status.lastRun.rowsFetched}, upserted ${status.lastRun.rowsUpserted}, deleted ${status.lastRun.rowsDeleted}.`
      );
    } else {
      toast('error', `Sync #${status.lastRun.id} failed: ${status.lastRun.errorMessage || 'unknown error'}`);
    }
  }

  return status.isRunning;
}

async function refreshRuns() {
  try {
    const { runs } = await api('/sync/runs?limit=20');
    const tbody = $('runs-tbody');
    tbody.innerHTML = '';
    for (const run of runs) {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${run.id}</td>
        <td><span class="status-pill ${run.status}">${run.status}</span></td>
        <td>${fmtDate(run.startedAt)}</td>
        <td>${run.finishedAt ? fmtDate(run.finishedAt) + ' (' + fmtDuration(run.startedAt, run.finishedAt) + ')' : '—'}</td>
        <td>${run.rowsFetched}</td>
        <td>${run.rowsUpserted}</td>
        <td>${run.rowsDeleted}</td>
        <td>${run.errorMessage ? escapeHtml(run.errorMessage).slice(0, 80) : ''}</td>
      `;
      tbody.appendChild(tr);
    }
  } catch (err) {
    // status refresh already surfaces connection errors; stay quiet here
  }
}

// ---------------------------------------------------------------------
// Event handlers
// ---------------------------------------------------------------------

$('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('login-error').hidden = true;
  try {
    // The real app login (not under /api/busy-sync — that's the
    // dashboard's own protected data, gated to the MANAGEMENT role).
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: $('username').value,
        password: $('password').value,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(body.error?.message || body.message || `Login failed (${res.status})`);
    }
    if (body.user?.role !== 'MANAGEMENT') {
      throw new Error('This dashboard is only available to Management accounts.');
    }
    setToken(body.token);
    showDashboard();
  } catch (err) {
    $('login-error').textContent = err.message;
    $('login-error').hidden = false;
  }
});

$('logout-btn').addEventListener('click', () => {
  setToken(null);
  showLogin();
});

$('trigger-btn').addEventListener('click', async () => {
  const btn = $('trigger-btn');
  btn.disabled = true;
  try {
    await api('/sync/trigger', { method: 'POST' });
    toast('info', 'Sync started.');
    scheduleNextPoll(0); // poll immediately to pick up the running state
  } catch (err) {
    toast('error', err.message);
    btn.disabled = false;
  }
});

$('validate-btn').addEventListener('click', async () => {
  const btn = $('validate-btn');
  const originalLabel = btn.textContent;
  btn.disabled = true;
  btn.textContent = 'Validating…';
  try {
    const result = await api('/sync/validate', { method: 'POST' });
    renderValidation(result);
    toast(result.pass ? 'success' : 'error', result.pass ? 'Validation passed.' : 'Validation found differences — see details below.');
  } catch (err) {
    toast('error', `Validation failed: ${err.message}`);
  } finally {
    btn.disabled = false;
    btn.textContent = originalLabel;
  }
});

function renderValidation(result) {
  const panel = $('validation-result');
  panel.hidden = false;

  const summary = $('validation-summary');
  summary.innerHTML = `
    <div class="card-value ${result.pass ? 'good' : 'bad'}">${result.pass ? 'PASS' : 'FAIL'}</div>
    <p>BUSY: ${result.busyCount} · MariaDB: ${result.mariaDbCount} ·
       Missing: ${result.missingInMariaDb.length} · Extra: ${result.extraInMariaDb.length} ·
       Different: ${result.differences.length}</p>
  `;

  const diffsEl = $('validation-diffs');
  diffsEl.innerHTML = '';
  for (const diff of result.differences.slice(0, 20)) {
    const row = document.createElement('div');
    row.className = 'diff-row';
    row.textContent = `Customer ${diff.customerId} — ${diff.field}: BUSY=${diff.busyValue} MariaDB=${diff.mariaDbValue}`;
    diffsEl.appendChild(row);
  }
}

if (getToken()) {
  showDashboard();
} else {
  showLogin();
}
