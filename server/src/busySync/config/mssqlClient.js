const mssql = require('mssql');
const logger = require('../../config/logger');
const { mssql: mssqlEnv } = require('./env');

/**
 * Resolves `host\INSTANCE` server strings — when a fixed port is also given,
 * connect by host:port instead (typical for static ports); only one of
 * instanceName/port is used.
 */
function resolveServer(rawServer, port) {
  let server = rawServer || '0.0.0.0';
  const options = {};
  if (server.includes('\\')) {
    const [host, instanceName] = server.split('\\');
    server = host;
    if (!port) options.instanceName = instanceName;
  }
  return { server, options };
}

/**
 * Builds a per-branch connection config. `conn` (server/port/user/password/
 * encrypt/trustServerCertificate/poolMin/poolMax/requestTimeout/
 * connectionTimeout) defaults to the original single-host `mssqlEnv` so
 * existing tp/claart call sites are unaffected; branches on a second BUSY
 * host (see config/branches.js) pass their own `conn` (e.g. `mssql2`).
 */
function buildConfig(database, conn = mssqlEnv) {
  const { server, options } = resolveServer(conn.server, conn.port);
  return {
    server,
    port: conn.port,
    database,
    user: conn.user,
    password: conn.password,
    options: {
      encrypt: conn.encrypt,
      trustServerCertificate: conn.trustServerCertificate,
      enableArithAbort: true,
      useUTC: true,
      ...options,
    },
    pool: {
      min: conn.poolMin,
      max: conn.poolMax,
      idleTimeoutMillis: 30000,
    },
    requestTimeout: conn.requestTimeout,
    connectionTimeout: conn.connectionTimeout,
  };
}

class MssqlConnection {
  constructor(database = mssqlEnv.database, conn = mssqlEnv) {
    this.database = database;
    this.conn = conn;
    this.pool = null;
    this._isConnected = false;
    this._lastError = null;
  }

  get isConnected() {
    return this._isConnected;
  }

  get lastError() {
    return this._lastError;
  }

  async connect() {
    const { server } = resolveServer(this.conn.server, this.conn.port);
    try {
      logger.info(`[BUSY ERP] Connecting to ${server}${this.conn.port ? ':' + this.conn.port : ''} / ${this.database}...`);
      this.pool = await new mssql.ConnectionPool(buildConfig(this.database, this.conn)).connect();

      this.pool.on('error', (err) => {
        this._isConnected = false;
        this._lastError = err.message;
        logger.error(`[BUSY ERP] Connection pool error — ERP went offline (${this.database}): ${err.message}`);
      });

      this._isConnected = true;
      this._lastError = null;
      logger.info(`[BUSY ERP] Connected successfully (${this.database}).`);
      return this.pool;
    } catch (err) {
      this._isConnected = false;
      this._lastError = err.message || String(err);
      logger.error(`[BUSY ERP] Connection failed (${this.database}): ${this._lastError}`);
      throw err;
    }
  }

  getPool() {
    if (!this.pool || !this._isConnected) {
      const errMsg = this._lastError
        ? `BUSY ERP is offline (${this.database}). Last error: ` + this._lastError
        : `BUSY ERP is not connected (${this.database}).`;
      throw new Error(errMsg);
    }
    return this.pool;
  }
}

// One MssqlConnection per host+database, created lazily and reused.
const poolsByDatabase = new Map();

/** Returns a *connected* MssqlConnection for `database` on `conn`'s host, connecting on first use. */
async function poolForDatabase(database, conn = mssqlEnv) {
  const db = database || mssqlEnv.database;
  const key = `${conn.server}:${conn.port}:${db}`;
  let entry = poolsByDatabase.get(key);
  if (!entry) {
    entry = new MssqlConnection(db, conn);
    poolsByDatabase.set(key, entry);
  }
  if (!entry.isConnected) {
    await entry.connect();
  }
  return entry;
}

// Back-compat singleton — the Turning Point / default database. Used by
// invoiceReport, receiptTotalsReport and the /sync/status route
// (mssqlDb.isConnected / .lastError). connect() is still called lazily by
// those callers.
const mssqlDb = new MssqlConnection();
poolsByDatabase.set(`${mssqlEnv.server}:${mssqlEnv.port}:${mssqlDb.database}`, mssqlDb);

module.exports = { MssqlConnection, mssqlDb, poolForDatabase, sql: mssql };
