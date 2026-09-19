const fs = require('fs');
const path = require('path');
const { sql, mssqlDb, poolForDatabase } = require('../config/mssqlClient');
const { parentGroupClause } = require('./parentGroupFilter');

const QUERY_PATH = path.resolve(__dirname, 'customerReport.mssql.sql');

/**
 * Canonical customer report shape, camelCase — mirrors
 * backend1/src/reports/customer/customerReport.types.ts's CustomerReport.
 * customerId, customerName, ledgerClosingBalance, balanceType,
 * lastReceiptDate, lastReceiptAmount, amountAlreadyDue, futureDueAmount,
 * age0_30, age31_60, age61_90, age90Plus, maxDaysOverdue,
 * outstandingStatus, mobile, gstNo, address, salesman, salesmanCode,
 * creditDays, creditLimit, branch.
 */
function mapRow(raw, branchLabel = 'Turning Point') {
  const ledgerClosingBalance = raw.LEDGER_CLOSING_BALANCE ?? 0;
  return {
    customerId: raw.CUSTOMER_ID,
    customerName: raw.CUSTOMER_NAME,

    ledgerClosingBalance,
    balanceType: raw.BALANCE_TYPE ?? null,

    lastReceiptDate: raw.LAST_RECEIPT_DATE ?? null,
    lastReceiptAmount: raw.LAST_RECEIPT_AMOUNT ?? null,

    // The outer SELECT now surfaces AMOUNT_ALREADY_DUE_NET_OF_ADVANCE (an
    // opening-credit-advance-netted figure), not the plain AMOUNT_ALREADY_DUE
    // column — see customerReport.mssql.sql's header comment.
    amountAlreadyDue: raw.AMOUNT_ALREADY_DUE_NET_OF_ADVANCE ?? 0,
    futureDueAmount: raw.FUTURE_DUE_AMOUNT ?? 0,

    age0_30: raw.AGE_0_30 ?? 0,
    age31_60: raw.AGE_31_60 ?? 0,
    age61_90: raw.AGE_61_90 ?? 0,
    age90Plus: raw.AGE_90_PLUS ?? 0,

    maxDaysOverdue: raw.MAX_DAYS_OVERDUE ?? null,
    // Not a BUSY column — the raw query doesn't compute this at the SQL
    // layer, so it's derived here (pure function of ledgerClosingBalance).
    outstandingStatus: ledgerClosingBalance > 0 ? 'OUTSTANDING' : 'SETTLED',

    mobile: raw.MOBILE ?? null,
    gstNo: raw.GSTNO ?? null,
    address: raw.ADDRESS ?? null,

    salesman: raw.SALESMAN ?? null,
    salesmanCode: raw.salesmancode ?? null,

    creditDays: raw.CREDIT_DAYS ?? null,
    creditLimit: raw.CREDIT_LIMIT ?? null,

    // Not a BUSY column — the query is scoped to one branch database +
    // PARENTGRP list, so the caller (customerAgeingSync's branch loop)
    // knows which branch every row belongs to and stamps it here.
    branch: branchLabel,
  };
}

/**
 * @param {{ limit?: number, salesmanCode?: number, customerId?: number|string,
 *           database?: string, parentGroups?: string[], branchLabel?: string,
 *           conn?: object }} [options]
 */
async function getCustomers(options = {}) {
  const conn = options.database ? await poolForDatabase(options.database, options.conn) : mssqlDb;
  if (!conn.isConnected) {
    await conn.connect();
  }

  let queryText = fs.readFileSync(QUERY_PATH, 'utf8');
  // T-SQL forbids ORDER BY inside a derived table unless that inner query
  // also has TOP/OFFSET — so wrapping the whole query in an outer
  // "SELECT TOP (n) * FROM (...) AS R" breaks, since this query already
  // ends with its own ORDER BY. Inject TOP into the query's own leading
  // SELECT instead, which is valid T-SQL and preserves the ORDER BY.
  if (options.limit) {
    queryText = queryText.replace(/^SELECT\b/m, `SELECT TOP (${Number(options.limit)})`);
  }

  queryText = queryText.replace('/*{{PARENTGRP_FILTER}}*/', parentGroupClause(options.parentGroups));

  const request = conn.getPool().request();
  const filters = [];
  if (options.salesmanCode != null) {
    request.input('salesmanCode', sql.Int, options.salesmanCode);
    filters.push('AND X.salesmancode = @salesmanCode');
  }
  if (options.customerId != null) {
    request.input('customerId', sql.Int, Number(options.customerId));
    filters.push('AND X.CUSTOMER_ID = @customerId');
  }
  queryText = queryText.replace('/*{{SALESMAN_FILTER}}*/', filters.join(' '));

  const result = await request.query(queryText);
  return result.recordset.map((r) => mapRow(r, options.branchLabel));
}

/** One customer, scoped to a salesman — both filters are applied server-side together, so a salesman can never fetch another's customer by guessing an ID. */
async function getCustomerByIdForSalesman(customerId, salesmanCode) {
  const rows = await getCustomers({ customerId, salesmanCode, limit: 1 });
  return rows[0] || null;
}

module.exports = { getCustomers, getCustomerByIdForSalesman, mapRow };
