/**
 * Canonical customer report contract. Both BUSY (MSSQL) and the
 * BUSY_SOURCE_DATA mirror (MariaDB) map their raw, database-specific
 * columns into this shape — nothing downstream should ever see a raw
 * MSSQL or MariaDB column name.
 *
 * Matches the updated BUSY query supplied directly (narrower than an
 * earlier version of this contract): no openingOutstanding /
 * currentYear* / lastReceipt* / email / asOfDate. `outstandingStatus`
 * is the one field kept beyond what the raw query returns — it's a pure
 * function of ledgerClosingBalance, computed the same way the original
 * query used to compute it at the SQL layer, now computed in the
 * repositories instead (see mssqlCustomerReportRepository.ts).
 */
export interface CustomerReport {
  customerId: number;
  customerName: string;

  ledgerClosingBalance: number;
  balanceType: string | null;

  lastInvoiceDate: Date | null;
  lastInvoiceAmount: number | null;

  amountAlreadyDue: number;
  futureDueAmount: number;

  age0_30: number;
  age31_60: number;
  age61_90: number;
  age90Plus: number;

  maxDaysOverdue: number | null;
  outstandingStatus: string | null;

  mobile: string | null;
  gstNo: string | null;
  address: string | null;

  salesman: string | null;
  salesmanCode: number | null;

  creditDays: number | null;
  creditLimit: number | null;
}

export interface CustomerReportOptions {
  /** Cap the number of rows returned (mainly for previews/smoke tests). */
  limit?: number;
  /** Restrict to one salesman's customers (matches CustomerReport.salesmanCode). */
  salesmanCode?: number;
}

/**
 * The application talks to this interface only — it never knows or cares
 * whether the data came from live BUSY (MSSQL) or the synchronized
 * MariaDB mirror.
 */
export interface CustomerReportRepository {
  getCustomers(options?: CustomerReportOptions): Promise<CustomerReport[]>;
}
