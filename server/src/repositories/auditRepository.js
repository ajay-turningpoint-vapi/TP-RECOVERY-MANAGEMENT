const { query } = require('../config/db');

/**
 * Appends one audit event for a customer. Every write path across every
 * domain (customers, tasks, ptps, disputes, escalations, payment claims)
 * calls this — a single, canonical place audit rows get created, so no
 * action can "forget" to log itself. Accepts an optional `connection` to
 * participate in an in-flight transaction.
 */
async function record(customerId, { type, description, actor, previousState, newState, source = 'App', attachmentPath }, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO audit_events (customer_id, type, description, actor, previous_state, new_state, source, attachment_path)
     VALUES (:customerId, :type, :description, :actor, :previousState, :newState, :source, :attachmentPath)`,
    { customerId, type, description, actor, previousState: previousState ?? null, newState: newState ?? null, source, attachmentPath: attachmentPath ?? null }
  );
}

/**
 * Deletes this customer's single most recent audit event of `type` — used
 * to erase a misrecorded No Answer when the salesman replaces it via
 * "Edit Recorded Outcome" (see customerService.recordOutcome's
 * `replacingNoAnswer` branch). The nested SELECT is required because
 * MariaDB/MySQL can't target the same table a DELETE is running against
 * directly in its own subquery.
 */
async function deleteLatestOfType(customerId, type, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `DELETE FROM audit_events WHERE id = (
       SELECT id FROM (
         SELECT id FROM audit_events WHERE customer_id = :customerId AND type = :type ORDER BY occurred_at DESC LIMIT 1
       ) AS latest
     )`,
    { customerId, type }
  );
}

function mapAuditEvent(row) {
  return {
    id: row.id,
    customerId: row.customer_id,
    type: row.type,
    description: row.description,
    actor: row.actor,
    previousState: row.previous_state,
    newState: row.new_state,
    source: row.source,
    occurredAt: row.occurred_at,
    attachmentPath: row.attachment_path,
  };
}

async function listForCustomer(customerId) {
  const rows = await query('SELECT * FROM audit_events WHERE customer_id = :customerId ORDER BY occurred_at DESC', { customerId });
  return rows.map(mapAuditEvent);
}

/** Every audit event, for batch server-side computations (e.g. scoringService's "days since last follow-up") that would otherwise be N+1 per-customer queries. */
async function listAll() {
  const rows = await query('SELECT * FROM audit_events ORDER BY occurred_at DESC');
  return rows.map(mapAuditEvent);
}

module.exports = { record, listForCustomer, listAll, deleteLatestOfType, mapAuditEvent };
