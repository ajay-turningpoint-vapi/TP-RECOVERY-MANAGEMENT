const { query } = require('../config/db');

/** The stored response for a previously-seen idempotency key, or null. */
async function find(key) {
  const rows = await query('SELECT status_code AS statusCode, response_body AS responseBody FROM idempotency_keys WHERE `key` = :key LIMIT 1', {
    key,
  });
  if (!rows[0]) return null;
  return { statusCode: rows[0].statusCode, responseBody: rows[0].responseBody };
}

/**
 * Records a route's response against a key, first-write-wins. Two requests
 * racing on the same key (a client retry firing before the first attempt's
 * response even lands) both execute — this only matters for which one's
 * response every later replay sees, not for preventing the double-execute
 * itself (the write-queue's own single-flight per customer is what
 * prevents that; see recovery-model docs). `INSERT IGNORE` rather than
 * upsert: the FIRST recorded response for a key is the one that must keep
 * being replayed forever, never overwritten by a later call.
 */
async function save(key, route, statusCode, responseBody) {
  await query('INSERT IGNORE INTO idempotency_keys (`key`, route, status_code, response_body) VALUES (:key, :route, :statusCode, :responseBody)', {
    key,
    route,
    statusCode,
    responseBody: JSON.stringify(responseBody),
  });
}

module.exports = { find, save };
