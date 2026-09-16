/**
 * Env config for the BUSY MSSQL connection — deliberately separate from
 * ../../config/env.js (the main app's strict `required()`-gated config).
 * BUSY connectivity is not required for the main API to boot (e.g. local
 * dev without network access to the ERP host), so this reads with
 * defaults instead of throwing at import time. Missing/wrong values
 * surface as real connection errors when a BUSY route/job actually runs,
 * not as a startup crash for the whole server.
 *
 * The MariaDB side of the sync (customer_ageing_snapshot, sync_runs, and
 * now `customers` itself) uses the main app's own database — see
 * ../../config/db.js — not a separate connection, since everything is
 * consolidated into one database.
 */

const mssql = {
  server: process.env.DB_SERVER || '',
  port: process.env.DB_PORT ? parseInt(process.env.DB_PORT, 10) : undefined,
  database: process.env.DB_DATABASE || '',
  user: process.env.DB_USER || '',
  password: process.env.DB_PASSWORD || '',
  encrypt: process.env.DB_ENCRYPT !== 'false',
  trustServerCertificate: process.env.DB_TRUST_SERVER_CERTIFICATE === 'true',
  poolMin: process.env.DB_POOL_MIN ? parseInt(process.env.DB_POOL_MIN, 10) : 2,
  poolMax: process.env.DB_POOL_MAX ? parseInt(process.env.DB_POOL_MAX, 10) : 20,
  requestTimeout: process.env.DB_REQUEST_TIMEOUT ? parseInt(process.env.DB_REQUEST_TIMEOUT, 10) : 120000,
  connectionTimeout: process.env.DB_CONNECTION_TIMEOUT ? parseInt(process.env.DB_CONNECTION_TIMEOUT, 10) : 30000,
};

// Second BUSY ERP host — FP-VAPI, FP-NAVSARI and PORSHIVE company databases
// live here instead of on `mssql`'s host (see config/branches.js). Same
// pool/timeout settings; only server/port/user/password differ per host.
const mssql2 = {
  ...mssql,
  server: process.env.BUSY2_DB_SERVER || '',
  port: process.env.BUSY2_DB_PORT ? parseInt(process.env.BUSY2_DB_PORT, 10) : undefined,
  database: '',
  user: process.env.BUSY2_DB_USER || '',
  password: process.env.BUSY2_DB_PASSWORD || '',
};

module.exports = { mssql, mssql2 };
