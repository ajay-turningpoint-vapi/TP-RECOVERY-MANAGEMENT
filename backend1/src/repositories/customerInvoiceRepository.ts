import { PoolConnection } from 'mysql2/promise';
import { withTransaction, query } from '../config/mariadb';
import { CustomerInvoiceReport } from '../reports/invoice/invoiceReport.types';
import logger from '../utils/logger';

const COLUMNS = [
  'ref_code',
  'customer_id',
  'customer_name',
  'invoice_date',
  'due_date',
  'invoice_no',
  'ref_amount',
  'pending_amount',
  'message',
  'last_synced_at',
] as const;

const UPDATABLE_COLUMNS = COLUMNS.filter((c) => c !== 'ref_code');

const CHUNK_SIZE = 200;

function toRowValues(row: CustomerInvoiceReport, syncStartedAt: Date): any[] {
  return [
    row.refCode,
    row.customerId,
    row.customerName,
    row.invoiceDate,
    row.dueDate,
    row.invoiceNo,
    row.refAmount,
    row.pendingAmount,
    row.message,
    syncStartedAt,
  ];
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

async function upsertChunk(
  connection: PoolConnection,
  rows: CustomerInvoiceReport[],
  syncStartedAt: Date
): Promise<void> {
  const placeholders = rows.map(() => `(${COLUMNS.map(() => '?').join(', ')})`).join(', ');
  const updateClause = UPDATABLE_COLUMNS.map((c) => `${c} = VALUES(${c})`).join(', ');
  const sql = `
    INSERT INTO customer_invoice_snapshot (${COLUMNS.join(', ')})
    VALUES ${placeholders}
    ON DUPLICATE KEY UPDATE ${updateClause}
  `;
  const values = rows.flatMap((row) => toRowValues(row, syncStartedAt));
  await connection.query(sql, values);
}

export async function syncInvoiceSnapshot(
  rows: CustomerInvoiceReport[],
  syncStartedAt: Date
): Promise<{ upserted: number; deleted: number }> {
  return withTransaction(async (connection) => {
    for (const batch of chunk(rows, CHUNK_SIZE)) {
      await upsertChunk(connection, batch, syncStartedAt);
    }

    const [deleteResult]: any = await connection.query(
      'DELETE FROM customer_invoice_snapshot WHERE last_synced_at < ?',
      [syncStartedAt]
    );

    logger.info(
      `[BUSY_INVOICE_DATA] Upserted ${rows.length} row(s), swept ${deleteResult.affectedRows} stale row(s).`
    );

    return { upserted: rows.length, deleted: deleteResult.affectedRows as number };
  });
}
