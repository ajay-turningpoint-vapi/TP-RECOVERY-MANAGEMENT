const fs = require('fs');
const path = require('path');
const { sql, mssqlDb, poolForDatabase } = require('../config/mssqlClient');
const { parentGroupClause } = require('./parentGroupFilter');

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
  const conn = options.database ? await poolForDatabase(options.database) : mssqlDb;
  if (!conn.isConnected) {
    await conn.connect();
  }

  let queryText = fs.readFileSync(QUERY_PATH, 'utf8');

  if (options.limit) {
    queryText = queryText.replace(/^SELECT\b/m, `SELECT TOP (${Number(options.limit)})`);
  }

  queryText = queryText.replace('/*{{PARENTGRP_FILTER}}*/', parentGroupClause(options.parentGroups));

  const request = conn.getPool().request();
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
