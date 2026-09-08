const fs = require('fs');
const path = require('path');
const { sql, mssqlDb } = require('../config/mssqlClient');

const QUERY_PATH = path.resolve(__dirname, 'invoiceReport.mssql.sql');

function mapRow(raw) {
  return {
    refCode: raw.ref_code,
    customerId: String(raw.customer_id),
    customerName: raw.customer_name,
    invoiceDate: raw.invoice_date,
    dueDate: raw.due_date,
    invoiceNo: raw.invoice_no,
    refAmount: raw.ref_amount ?? 0,
    pendingAmount: raw.pending_amount ?? 0,
    dueDays: raw.due_days == null ? null : Number(raw.due_days),
    message: raw.message ?? '',
  };
}

async function getInvoices(options = {}) {
  if (!mssqlDb.isConnected) {
    await mssqlDb.connect();
  }

  let queryText = fs.readFileSync(QUERY_PATH, 'utf8');

  if (options.limit) {
    queryText = queryText.replace(/^SELECT\b/m, `SELECT TOP (${Number(options.limit)})`);
  }

  const request = mssqlDb.getPool().request();
  if (options.customerId != null) {
    request.input('customerId', sql.Int, options.customerId);
    queryText = queryText.replace('/*{{CUSTOMER_FILTER}}*/', 'AND M.Code = @customerId');
  } else {
    queryText = queryText.replace('/*{{CUSTOMER_FILTER}}*/', '');
  }

  const result = await request.query(queryText);
  return result.recordset.map(mapRow);
}

module.exports = { getInvoices, mapRow };
