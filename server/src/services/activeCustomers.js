const customerRepository = require('../repositories/customerRepository');

/**
 * A customer BUSY no longer has (busy_still_active = 0) is removed from RMS
 * as far as anyone using it can tell: none of their tasks, PTPs, claims,
 * disputes, escalations or notifications leave the server — not in lists,
 * not in reports, not in salesman figures. The rows stay in the database
 * (background jobs still see them, and if BUSY brings the customer back
 * their history returns).
 *
 * Applied where data leaves the server, never inside the repositories the
 * jobs share (same split as taskRepository.findAllForActiveCustomers).
 */
async function withoutRemoved(rows) {
  const removed = await customerRepository.findRemovedIds();
  if (removed.size === 0) return rows;
  return rows.filter((r) => !r.customerId || !removed.has(r.customerId));
}

/** SQL fragment for raw report queries on a table with a customer_id column. */
const NOT_REMOVED_SQL = 'customer_id NOT IN (SELECT id FROM customers WHERE busy_still_active = 0)';

module.exports = { withoutRemoved, NOT_REMOVED_SQL };
