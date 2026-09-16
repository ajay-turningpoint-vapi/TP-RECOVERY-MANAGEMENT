const fs = require('fs');
const path = require('path');
const { sql, mssqlDb, poolForDatabase } = require('../config/mssqlClient');
const { parentGroupClause } = require('./parentGroupFilter');

const QUERY_PATH = path.resolve(__dirname, 'receiptTotalsReport.mssql.sql');

function mapRow(raw) {
  return {
    // customers.id IS String(BUSY M.CODE) — see customerRepository.upsertFromBusy.
    // Match PTPs by this id, never by CUSTOMER_NAME.
    customerId: String(raw.CUSTOMER_ID),
    customerName: raw.CUSTOMER_NAME,
    totalEntries: raw.TOTAL_ENTRIES, // informational only — never used for the verification decision
    // Receipt (VchType 14) / Journal (VchType 16) breakdown — informational
    // only (e.g. audit/debugging), same status as totalEntries. The
    // verification decision (services/ptpVerificationService.js) is made
    // purely on totalAmount, their combined sum.
    receiptAmount: Number(raw.RECEIPT_AMOUNT) || 0,
    journalAmount: Number(raw.JOURNAL_AMOUNT) || 0,
    totalAmount: Number(raw.TOTAL_AMOUNT) || 0,
  };
}

/**
 * Per-customer BUSY receipt totals for [startDate, endDate] (inclusive,
 * compared against the BUSY transaction date). Used by
 * services/ptpVerificationService.js to check whether a promised payment
 * actually landed in BUSY within a PTP's eligible window.
 *
 * `database` / `parentGroups` scope the query to one branch's BUSY company
 * database + PARENTGRP list (config/branches.js). Omitting them keeps the
 * historical Turning Point-only behaviour.
 *
 * @param {{ startDate: string, endDate: string, database?: string, parentGroups?: string[], conn?: object }} opts
 */
async function getReceiptTotals({ startDate, endDate, database, parentGroups, conn: hostConn }) {
  const conn = database ? await poolForDatabase(database, hostConn) : mssqlDb;
  if (!conn.isConnected) {
    await conn.connect();
  }

  let queryText = fs.readFileSync(QUERY_PATH, 'utf8');
  queryText = queryText.replace('/*{{PARENTGRP_FILTER}}*/', parentGroupClause(parentGroups));

  const request = conn.getPool().request();
  request.input('startDate', sql.Date, startDate);
  request.input('endDate', sql.Date, endDate);

  const result = await request.query(queryText);
  return result.recordset.map(mapRow);
}

module.exports = { getReceiptTotals, mapRow };
