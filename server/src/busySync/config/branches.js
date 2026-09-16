/**
 * The BUSY branches this app syncs from. Each branch is one BUSY *company*
 * database, scoped to its own PARENTGRP code list, and now also carries its
 * own `conn` (server/port/login — see config/env.js's `mssql`/`mssql2`):
 * tp/claart share the original host, fpvapi/fpnavsari/porshive live on a
 * second BUSY host with a different SQL login. The customer-ageing sync
 * (sync/customerAgeingSync.js) loops these in order in a single run.
 *
 * `parentGroups`, `label` and `nameSuffix` are query-structural and live
 * here next to the SQL. Database names are environment-specific: each
 * branch reads its own `*_DB_DATABASE` env var, with a hard fallback so a
 * fresh checkout still knows the name.
 *
 * `label` is written verbatim to `users.branch` / `customers.branch` /
 * `customer_ageing_snapshot.branch` and is what the app's branch filters
 * match on. `nameSuffix` is appended to every salesman's display name
 * (`users.full_name`) so an "All Branches" view can tell two same-named
 * salesmen apart.
 */
const { mssql, mssql2 } = require('./env');

const BRANCHES = [
  {
    key: 'tp',
    label: 'Turning Point',
    nameSuffix: ' -TP',
    database: mssql.database || 'BusyComp0002_db12026',
    parentGroups: ['574140', '574141', '258335', '577533'],
    conn: mssql,
  },
  {
    key: 'claart',
    label: 'Claart',
    nameSuffix: ' -Claart',
    database: process.env.CLAART_DB_DATABASE || 'BusyComp0011_db12026',
    parentGroups: ['258335', '652099', '574141', '166'],
    conn: mssql,
  },
  // These 3 branches live on a second BUSY host (192.168.1.128:1441, see
  // config/env.js's `mssql2`) with its own SQL login — different server
  // from tp/claart above.
  {
    key: 'fpvapi',
    label: 'FP-VAPI',
    nameSuffix: ' -FPVAPI',
    database: process.env.FPVAPI_DB_DATABASE || 'BusyComp0001_db12026',
    parentGroups: ['15723', '15039', '116', '13475'],
    conn: mssql2,
  },
  {
    key: 'fpnavsari',
    label: 'FP-NAVSARI',
    nameSuffix: ' -FPNAVSARI',
    database: process.env.FPNAVSARI_DB_DATABASE || 'BusyComp0003_db12026',
    parentGroups: ['19712', '19713', '19711'],
    conn: mssql2,
  },
  {
    key: 'porshive',
    label: 'PORSHIVE',
    nameSuffix: ' -PORSHIVE',
    database: process.env.PORSHIVE_DB_DATABASE || 'BusyComp0006_db12026',
    parentGroups: ['1757', '1758', '1759'],
    conn: mssql2,
  },
];

module.exports = { BRANCHES };
