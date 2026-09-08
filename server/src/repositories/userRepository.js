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

module.exports = { findByUsername, findById, listSalesmen, findAll, updatePasswordHash };
