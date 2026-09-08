const fs = require('fs');
const path = require('path');
const { query } = require('../../config/db');

const QUERY_PATH = path.resolve(__dirname, 'customerReport.mariadb.sql');

/**
 * DATE columns come back as 'YYYY-MM-DD' strings (see
 * config/db.js's dateStrings setting) — parse as UTC midnight to match
 * how the mssql driver represents BUSY's dates, so the two sides compare
 * equal.
 */
function parseDateOnly(v) {
  if (!v) return null;
  if (v instanceof Date) return v;
  return new Date(`${v}T00:00:00.000Z`);
}

function normalize(raw) {
  const num = (v) => (v === null || v === undefined ? 0 : Number(v));
  const numOrNull = (v) => (v === null || v === undefined ? null : Number(v));

  return {
    customerId: raw.customerId,
    customerName: raw.customerName,

    ledgerClosingBalance: num(raw.ledgerClosingBalance),
    balanceType: raw.balanceType ?? null,

    lastReceiptDate: parseDateOnly(raw.lastReceiptDate),
    lastReceiptAmount: numOrNull(raw.lastReceiptAmount),

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

/**
 * @param {{ limit?: number, salesmanCode?: number, customerId?: number|string }} [options]
 */
async function getCustomers(options = {}) {
  let sqlText = fs.readFileSync(QUERY_PATH, 'utf8');
  const params = [];
  const filters = [];

  if (options.salesmanCode != null) {
    filters.push('AND salesman_code = ?');
    params.push(options.salesmanCode);
  }
  if (options.customerId != null) {
    filters.push('AND customer_id = ?');
    params.push(options.customerId);
  }

  sqlText = sqlText.replace('/*{{SALESMAN_FILTER}}*/', filters.join(' '));

  if (options.limit) {
    sqlText = `${sqlText.trim()}\nLIMIT ${Number(options.limit)}`;
  }

  const rows = await query(sqlText, params);
  return rows.map(normalize);
}

/** One customer, scoped to a salesman — a salesman can never fetch another's customer by guessing an ID, since both filters are applied server-side together. */
async function getCustomerByIdForSalesman(customerId, salesmanCode) {
  const rows = await getCustomers({ customerId, salesmanCode, limit: 1 });
  return rows[0] || null;
}

module.exports = { getCustomers, getCustomerByIdForSalesman, normalize };
