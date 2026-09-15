import { PoolConnection } from 'mysql2/promise';
import { withTransaction, query } from '../config/mariadb';
import { CustomerReport } from '../reports/customer/customerReport.types';
import logger from '../utils/logger';

const COLUMNS = [
  'customer_id',
  'branch_id',
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

// customer_id + branch_id together are the primary key — never in the UPDATE set.
const UPDATABLE_COLUMNS = COLUMNS.filter((c) => c !== 'customer_id' && c !== 'branch_id');

const CHUNK_SIZE = 200;

function toRowValues(row: CustomerReport, syncStartedAt: Date, branchId: string): any[] {
  return [
    row.customerId,
    branchId,
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
  syncStartedAt: Date,
  branchId: string
): Promise<void> {
  const placeholders = rows.map(() => `(${COLUMNS.map(() => '?').join(', ')})`).join(', ');
  const updateClause = UPDATABLE_COLUMNS.map((c) => `${c} = VALUES(${c})`).join(', ');
  const sql = `
    INSERT INTO customer_ageing_snapshot (${COLUMNS.join(', ')})
    VALUES ${placeholders}
    ON DUPLICATE KEY UPDATE ${updateClause}
  `;
  const values = rows.flatMap((row) => toRowValues(row, syncStartedAt, branchId));
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
  syncStartedAt: Date,
  branchId: string
): Promise<{ upserted: number; deleted: number }> {
  return withTransaction(async (connection) => {
    for (const batch of chunk(rows, CHUNK_SIZE)) {
      await upsertChunk(connection, batch, syncStartedAt, branchId);
    }

    // Scope the stale-row sweep to THIS branch — syncing branch A must
    // never delete branch B's rows.
    const [deleteResult]: any = await connection.query(
      'DELETE FROM customer_ageing_snapshot WHERE branch_id = ? AND last_synced_at < ?',
      [branchId, syncStartedAt]
    );

    logger.info(
      `[BUSY_SOURCE_DATA] Branch ${branchId}: upserted ${rows.length} row(s), swept ${deleteResult.affectedRows} stale row(s).`
    );

    return { upserted: rows.length, deleted: deleteResult.affectedRows as number };
  });
}

export async function getTotalCustomerCount(): Promise<number> {
  const rows = await query<any[]>('SELECT COUNT(*) as c FROM customer_ageing_snapshot');
  return rows[0].c;
}

export type CustomerAgeingRow = CustomerReport & { branchId: string };

const num = (v: any): number => (v === null || v === undefined ? 0 : Number(v));
const numOrNull = (v: any): number | null => (v === null || v === undefined ? null : Number(v));
const parseDateOnly = (v: any): Date | null => {
  if (!v) return null;
  if (v instanceof Date) return v;
  return new Date(`${v}T00:00:00.000Z`);
};

/**
 * Reads the mirrored customer ageing rows, optionally scoped to one
 * branch. `branchId` omitted or 'all' → every branch. Rows carry their
 * own `branchId` so an "All" caller can still tell them apart.
 */
export async function getCustomersFromSnapshot(
  opts: { branchId?: string | null } = {}
): Promise<CustomerAgeingRow[]> {
  const all = !opts.branchId || opts.branchId === 'all';
  const sql = `
    SELECT
      customer_id AS customerId, branch_id AS branchId, customer_name AS customerName,
      ledger_closing_balance AS ledgerClosingBalance, balance_type AS balanceType,
      last_invoice_date AS lastInvoiceDate, last_invoice_amount AS lastInvoiceAmount,
      amount_already_due AS amountAlreadyDue, future_due_amount AS futureDueAmount,
      age_0_30 AS age0_30, age_31_60 AS age31_60, age_61_90 AS age61_90, age_90_plus AS age90Plus,
      max_days_overdue AS maxDaysOverdue, outstanding_status AS outstandingStatus,
      mobile, gstno AS gstNo, address,
      salesman, salesman_code AS salesmanCode,
      credit_days AS creditDays, credit_limit AS creditLimit
    FROM customer_ageing_snapshot
    ${all ? '' : 'WHERE branch_id = ?'}
    ORDER BY customer_name`;

  const rows = await query<any[]>(sql, all ? [] : [opts.branchId]);
  return rows.map((raw) => ({
    customerId: raw.customerId,
    branchId: raw.branchId,
    customerName: raw.customerName,
    ledgerClosingBalance: num(raw.ledgerClosingBalance),
    balanceType: raw.balanceType ?? null,
    lastInvoiceDate: parseDateOnly(raw.lastInvoiceDate),
    lastInvoiceAmount: numOrNull(raw.lastInvoiceAmount),
    amountAlreadyDue: num(raw.amountAlreadyDue),
    futureDueAmount: num(raw.futureDueAmount),
    age0_30: num(raw.age0_30),
    age31_60: num(raw.age31_60),
    age61_90: num(raw.age61_90),
    age90Plus: num(raw.age90Plus),
    maxDaysOverdue: numOrNull(raw.maxDaysOverdue),
    outstandingStatus: raw.outstandingStatus ?? null,
    mobile: raw.mobile ?? null,
    gstNo: raw.gstNo ?? null,
    address: raw.address ?? null,
    salesman: raw.salesman ?? null,
    salesmanCode: raw.salesmanCode ?? null,
    creditDays: numOrNull(raw.creditDays),
    creditLimit: numOrNull(raw.creditLimit),
  }));
}
