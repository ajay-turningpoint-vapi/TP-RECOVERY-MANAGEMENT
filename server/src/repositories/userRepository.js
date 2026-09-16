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

/** Bumps `session_version` and returns the new value — invalidates every access token issued before this call (see migration 028). */
async function bumpSessionVersion(id) {
  await query('UPDATE users SET session_version = session_version + 1 WHERE id = :id', { id });
  const rows = await query('SELECT session_version FROM users WHERE id = :id', { id });
  return rows[0]?.session_version ?? 1;
}

function getSessionVersion(id) {
  return query('SELECT session_version FROM users WHERE id = :id', { id }).then((rows) => rows[0]?.session_version ?? null);
}

module.exports = { findByUsername, findById, listSalesmen, findAll, updatePasswordHash, bumpSessionVersion, getSessionVersion };
