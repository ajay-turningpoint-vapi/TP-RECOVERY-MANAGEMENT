const { withTransaction } = require('../../config/db');
const logger = require('../../config/logger');

const COLUMNS = [
  'ref_code',
  'customer_id',
  'customer_name',
  'invoice_date',
  'due_date',
  'due_days',
  'invoice_no',
  'ref_amount',
  'pending_amount',
  'message',
  'last_synced_at',
];

const UPDATABLE_COLUMNS = COLUMNS.filter((c) => c !== 'ref_code');
const CHUNK_SIZE = 200;

function toRowValues(row, syncStartedAt) {
  return [
    row.refCode,
    row.customerId,
    row.customerName,
    row.invoiceDate,
    row.dueDate,
    row.dueDays ?? null,
    row.invoiceNo,
    row.refAmount,
    row.pendingAmount,
    row.message,
    syncStartedAt,
  ];
}

function chunk(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

async function upsertChunk(connection, rows, syncStartedAt) {
  const placeholders = rows.map(() => `(${COLUMNS.map(() => '?').join(', ')})`).join(', ');
  const updateClause = UPDATABLE_COLUMNS.map((c) => `${c} = VALUES(${c})`).join(', ');
  const sqlQuery = `
    INSERT INTO customer_invoice_snapshot (${COLUMNS.join(', ')})
    VALUES ${placeholders}
    ON DUPLICATE KEY UPDATE ${updateClause}
  `;
  const values = rows.flatMap((row) => toRowValues(row, syncStartedAt));
  await connection.query(sqlQuery, values);
}

async function syncInvoiceSnapshot(rows, syncStartedAt) {
  return withTransaction(async (connection) => {
    for (const batch of chunk(rows, CHUNK_SIZE)) {
      await upsertChunk(connection, batch, syncStartedAt);
    }

    const [deleteResult] = await connection.query(
      'DELETE FROM customer_invoice_snapshot WHERE last_synced_at < ?',
      [syncStartedAt]
    );

    logger.info(
      `[BUSY_INVOICE_DATA] Upserted ${rows.length} row(s), swept ${deleteResult.affectedRows} stale row(s).`
    );

    return { upserted: rows.length, deleted: deleteResult.affectedRows };
  });
}

module.exports = { syncInvoiceSnapshot };
