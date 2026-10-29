const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

/**
 * Record (or refresh) an RE's "mark complete" for a salesman. The
 * underperformance nudge itself only ever appears on the 1st of the month
 * (see re_tasks_screen.dart), so in practice this is only ever called that
 * day — but it's keyed on the real date, not just a month number, so the
 * history stays meaningful if that ever changes.
 */
async function dismiss(salesmanId, reId) {
  await query(
    `INSERT INTO re_underperformance_dismissals (id, salesman_id, dismissed_date, dismissed_by)
     VALUES (:id, :salesmanId, CURDATE(), :reId)
     ON DUPLICATE KEY UPDATE dismissed_by = :reId, created_at = CURRENT_TIMESTAMP`,
    { id: uuid(), salesmanId, reId }
  );
}

/**
 * Salesman ids dismissed within the current calendar month — the
 * underperformance nudge is monthly (raised on the 1st), so a dismissal
 * must hold for the rest of that month, not just the day it was clicked.
 */
async function dismissedThisMonthIds() {
  const rows = await query(
    `SELECT salesman_id FROM re_underperformance_dismissals
     WHERE YEAR(dismissed_date) = YEAR(CURDATE()) AND MONTH(dismissed_date) = MONTH(CURDATE())`
  );
  return rows.map((r) => r.salesman_id);
}

module.exports = { dismiss, dismissedThisMonthIds };
