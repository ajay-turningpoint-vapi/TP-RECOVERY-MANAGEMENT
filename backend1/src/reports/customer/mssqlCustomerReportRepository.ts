import fs from 'fs';
import path from 'path';
import sql from 'mssql';
import mssqlDb from '../../config/mssql';
import {
  CustomerReport,
  CustomerReportOptions,
  CustomerReportRepository,
} from './customerReport.types';

const QUERY_PATH = path.resolve(__dirname, 'customerReport.mssql.sql');

function mapRow(raw: any): CustomerReport {
  const ledgerClosingBalance = raw.LEDGER_CLOSING_BALANCE ?? 0;
  return {
    customerId: raw.CUSTOMER_ID,
    customerName: raw.CUSTOMER_NAME,

    ledgerClosingBalance,
    balanceType: raw.BALANCE_TYPE ?? null,

    lastInvoiceDate: raw.LAST_INVOICE_DATE ?? null,
    lastInvoiceAmount: raw.LAST_INVOICE_AMOUNT ?? null,

    amountAlreadyDue: raw.AMOUNT_ALREADY_DUE ?? 0,
    futureDueAmount: raw.FUTURE_DUE_AMOUNT ?? 0,

    age0_30: raw.AGE_0_30 ?? 0,
    age31_60: raw.AGE_31_60 ?? 0,
    age61_90: raw.AGE_61_90 ?? 0,
    age90Plus: raw.AGE_90_PLUS ?? 0,

    maxDaysOverdue: raw.MAX_DAYS_OVERDUE ?? null,
    // Not a BUSY column — the raw query no longer computes this at the
    // SQL layer, so it's derived here the same way the query used to.
    outstandingStatus: ledgerClosingBalance > 0 ? 'OUTSTANDING' : 'SETTLED',

    mobile: raw.MOBILE ?? null,
    gstNo: raw.GSTNO ?? null,
    address: raw.ADDRESS ?? null,

    salesman: raw.SALESMAN ?? null,
    salesmanCode: raw.slesmancode ?? null,

    creditDays: raw.CREDIT_DAYS ?? null,
    creditLimit: raw.CREDIT_LIMIT ?? null,
  };
}

export class MssqlCustomerReportRepository implements CustomerReportRepository {
  async getCustomers(options?: CustomerReportOptions): Promise<CustomerReport[]> {
    if (!mssqlDb.isConnected) {
      await mssqlDb.connect();
    }

    let queryText = fs.readFileSync(QUERY_PATH, 'utf8');
    // T-SQL forbids ORDER BY inside a derived table unless that inner
    // query also has TOP/OFFSET — so wrapping the whole query in an outer
    // "SELECT TOP (n) * FROM (...) AS R" breaks, since this query already
    // ends with its own ORDER BY. Inject TOP into the query's own leading
    // SELECT instead, which is valid T-SQL and preserves the ORDER BY.
    if (options?.limit) {
      queryText = queryText.replace(/^SELECT\b/m, `SELECT TOP (${Number(options.limit)})`);
    }

    const request = mssqlDb.getPool().request();
    if (options?.salesmanCode != null) {
      request.input('salesmanCode', sql.Int, options.salesmanCode);
      queryText = queryText.replace('/*{{SALESMAN_FILTER}}*/', 'AND X.slesmancode = @salesmanCode');
    } else {
      queryText = queryText.replace('/*{{SALESMAN_FILTER}}*/', '');
    }

    const result = await request.query(queryText);
    return result.recordset.map(mapRow);
  }
}
