import fs from 'fs';
import path from 'path';
import { query } from '../../config/mariadb';
import {
  CustomerReport,
  CustomerReportOptions,
  CustomerReportRepository,
} from './customerReport.types';

const QUERY_PATH = path.resolve(__dirname, 'customerReport.mariadb.sql');

/**
 * mysql2 returns DECIMAL columns as strings and DATE columns as Date
 * objects already — normalize the numeric ones so the canonical
 * CustomerReport always carries real numbers, matching what the MSSQL
 * repository returns.
 */
/**
 * DATE columns come back as 'YYYY-MM-DD' strings (see config/mariadb.ts's
 * dateStrings setting) — parse as UTC midnight to match how the mssql
 * driver represents BUSY's dates, so the two sides compare equal.
 */
function parseDateOnly(v: any): Date | null {
  if (!v) return null;
  if (v instanceof Date) return v;
  return new Date(`${v}T00:00:00.000Z`);
}

function normalize(raw: any): CustomerReport {
  const num = (v: any): number => (v === null || v === undefined ? 0 : Number(v));
  const numOrNull = (v: any): number | null => (v === null || v === undefined ? null : Number(v));

  return {
    customerId: raw.customerId,
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
  };
}

export class MariaDbCustomerReportRepository implements CustomerReportRepository {
  async getCustomers(options?: CustomerReportOptions): Promise<CustomerReport[]> {
    let sql = fs.readFileSync(QUERY_PATH, 'utf8');
    const params: any[] = [];

    if (options?.salesmanCode != null) {
      sql = sql.replace('/*{{SALESMAN_FILTER}}*/', 'AND salesman_code = ?');
      params.push(options.salesmanCode);
    } else {
      sql = sql.replace('/*{{SALESMAN_FILTER}}*/', '');
    }

    if (options?.limit) {
      sql = `${sql.trim()}\nLIMIT ${Number(options.limit)}`;
    }

    const rows = await query<any[]>(sql, params);
    return rows.map(normalize);
  }
}
