/**
 * The BUSY branches this app syncs from. Each branch is one BUSY *company*
 * database on the same MSSQL server / same login (see config/env.js's
 * `mssql`), scoped to its own PARENTGRP code list. The customer-ageing
 * sync (sync/customerAgeingSync.js) loops these in order in a single run.
 *
 * `parentGroups`, `label` and `nameSuffix` are query-structural and live
 * here next to the SQL. Only the database name is environment-specific:
 * Turning Point defaults to the existing `DB_DATABASE`, Claart to
 * `CLAART_DB_DATABASE` (with a hard fallback so a fresh checkout still
 * knows the name).
 *
 * `label` is written verbatim to `users.branch` / `customers.branch` /
 * `customer_ageing_snapshot.branch` and is what the app's branch filters
 * match on. `nameSuffix` is appended to every salesman's display name
 * (`users.full_name`) so an "All Branches" view can tell two same-named
 * salesmen apart.
 */
const { mssql } = require('./env');

const BRANCHES = [
  {
    key: 'tp',
    label: 'Turning Point',
    nameSuffix: ' -TP',
    database: mssql.database || 'BusyComp0002_db12026',
    parentGroups: ['574140', '574141', '258335', '577533'],
  },
  {
    key: 'claart',
    label: 'Claart',
    nameSuffix: ' -Claart',
    database: process.env.CLAART_DB_DATABASE || 'BusyComp0011_db12026',
    parentGroups: ['258335', '652099', '574141', '166'],
  },
];

module.exports = { BRANCHES };
