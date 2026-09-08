const { query } = require('../config/db');

/** Base salesperson rows — every real, derived roster figure (recovery score, collection %, task completion, etc.) is computed by salesmanService from real customers/ptps/tasks, not stored here. */
async function findAllSalespersons() {
  return query(
    `SELECT id, username, full_name AS fullName, branch, phone, busy_salesman_code AS busySalesmanCode FROM users WHERE role = 'SALESPERSON' ORDER BY full_name`
  );
}

module.exports = { findAllSalespersons };
