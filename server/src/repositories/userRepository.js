const { query } = require('../config/db');

function findByUsername(username) {
  return query('SELECT * FROM users WHERE username = :username LIMIT 1', { username }).then((rows) => rows[0] || null);
}

function findById(id) {
  return query('SELECT * FROM users WHERE id = :id LIMIT 1', { id }).then((rows) => rows[0] || null);
}

function listSalesmen() {
  return query("SELECT * FROM users WHERE role = 'SALESPERSON' ORDER BY full_name");
}

function findAll() {
  return query('SELECT * FROM users ORDER BY full_name');
}

function updatePasswordHash(id, passwordHash) {
  return query('UPDATE users SET password_hash = :passwordHash WHERE id = :id', { id, passwordHash });
}

// One session-version column per login channel (migrations 028 / 040) —
// the mobile app and the RE web dashboard each keep their own single session.
const SESSION_COLUMN = { mobile: 'session_version', web: 'web_session_version' };

function sessionColumn(channel) {
  return SESSION_COLUMN[channel] || SESSION_COLUMN.mobile;
}

/** Bumps the channel's session version and returns the new value — invalidates every access token that channel issued before this call (see migrations 028 / 040). */
async function bumpSessionVersion(id, channel = 'mobile') {
  const col = sessionColumn(channel);
  await query(`UPDATE users SET ${col} = ${col} + 1 WHERE id = :id`, { id });
  const rows = await query(`SELECT ${col} AS v FROM users WHERE id = :id`, { id });
  return rows[0]?.v ?? 1;
}

function getSessionVersion(id, channel = 'mobile') {
  const col = sessionColumn(channel);
  return query(`SELECT ${col} AS v FROM users WHERE id = :id`, { id }).then((rows) => rows[0]?.v ?? null);
}

module.exports = { findByUsername, findById, listSalesmen, findAll, updatePasswordHash, bumpSessionVersion, getSessionVersion };
