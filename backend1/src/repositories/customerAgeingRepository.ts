import { PoolConnection } from 'mysql2/promise';
import { withTransaction, query } from '../config/mariadb';
import { CustomerReport } from '../reports/customer/customerReport.types';
import logger from '../utils/logger';

const COLUMNS = [
  'customer_id',
  'customer_name',
  'ledger_closing_balance',
  'balance_type',
  'amount_already_due',
  'future_due_amount',
  'age_0_30',
  'age_31_60',
  'age_61_90',
  'age_90_plus',
  'max_days_overdue',
  'outstanding_status',
  'last_invoice_date',
  'last_invoice_amount',
  'mobile',
  'gstno',
  'address',
  'salesman',
  'salesman_code',
  'credit_days',
  'credit_limit',
  'last_synced_at',
] as const;

const UPDATABLE_COLUMNS = COLUMNS.filter((c) => c !== 'customer_id');

const CHUNK_SIZE = 200;

function toRowValues(row: CustomerReport, syncStartedAt: Date): any[] {
  return [
    row.customerId,
    row.customerName,
    row.ledgerClosingBalance,
    row.balanceType,
    row.amountAlreadyDue,
    row.futureDueAmount,
    row.age0_30,
    row.age31_60,
    row.age61_90,
    row.age90Plus,
    row.maxDaysOverdue,
    row.outstandingStatus,
    row.lastInvoiceDate,
    row.lastInvoiceAmount,
    row.mobile,
    row.gstNo,
    row.address,
    row.salesman,
    row.salesmanCode,
    row.creditDays,
    row.creditLimit,
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
  rows: CustomerReport[],
  syncStartedAt: Date
): Promise<void> {
  const placeholders = rows.map(() => `(${COLUMNS.map(() => '?').join(', ')})`).join(', ');
  const updateClause = UPDATABLE_COLUMNS.map((c) => `${c} = VALUES(${c})`).join(', ');
  const sql = `
    INSERT INTO customer_ageing_snapshot (${COLUMNS.join(', ')})
    VALUES ${placeholders}
    ON DUPLICATE KEY UPDATE ${updateClause}
  `;
  const values = rows.flatMap((row) => toRowValues(row, syncStartedAt));
  await connection.query(sql, values);
}

/**
 * Upserts every row from the latest BUSY pull, then deletes any row that
 * wasn't touched by this run (last_synced_at predates syncStartedAt) —
 * BUSY is the source of truth, so anything that fell out of the source
 * query's result set (e.g. a customer that's now CR/settled) must be
 * removed here too. Runs as one transaction: a failure rolls back the
 * whole run, leaving yesterday's data intact rather than half-updated.
 */
export async function syncSnapshot(
  rows: CustomerReport[],
  syncStartedAt: Date
): Promise<{ upserted: number; deleted: number }> {
  return withTransaction(async (connection) => {
    for (const batch of chunk(rows, CHUNK_SIZE)) {
      await upsertChunk(connection, batch, syncStartedAt);
    }

    const [deleteResult]: any = await connection.query(
      'DELETE FROM customer_ageing_snapshot WHERE last_synced_at < ?',
      [syncStartedAt]
    );

    logger.info(
      `[BUSY_SOURCE_DATA] Upserted ${rows.length} row(s), swept ${deleteResult.affectedRows} stale row(s).`
    );

    return { upserted: rows.length, deleted: deleteResult.affectedRows as number };
  });
}

export async function getTotalCustomerCount(): Promise<number> {
  const rows = await query<any[]>('SELECT COUNT(*) as c FROM customer_ageing_snapshot');
  return rows[0].c;
}
