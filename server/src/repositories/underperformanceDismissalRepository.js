const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

/** Record (or refresh) an RE's "mark complete" for a salesman for today. */
async function dismiss(salesmanId, reId) {
  await query(
    `INSERT INTO re_underperformance_dismissals (id, salesman_id, dismissed_date, dismissed_by)
     VALUES (:id, :salesmanId, CURDATE(), :reId)
     ON DUPLICATE KEY UPDATE dismissed_by = :reId, created_at = CURRENT_TIMESTAMP`,
    { id: uuid(), salesmanId, reId }
  );
}

/** Salesman ids dismissed for the current calendar day. */
async function dismissedTodayIds() {
  const rows = await query(
    "SELECT salesman_id FROM re_underperformance_dismissals WHERE dismissed_date = CURDATE()"
  );
  return rows.map((r) => r.salesman_id);
}

module.exports = { dismiss, dismissedTodayIds };
