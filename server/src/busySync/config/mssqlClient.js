const mssql = require('mssql');
const logger = require('../../config/logger');
const { mssql: mssqlEnv } = require('./env');

const rawServer = mssqlEnv.server || '0.0.0.0';
const port = mssqlEnv.port;

let server = rawServer;
const baseOptions = {
  encrypt: mssqlEnv.encrypt,
  trustServerCertificate: mssqlEnv.trustServerCertificate,
  enableArithAbort: true,
  useUTC: true,
};

// host\INSTANCE — when a fixed port is also given, connect by host:port
// instead (typical for static ports); only one of instanceName/port is used.
if (rawServer.includes('\\')) {
  const [host, instanceName] = rawServer.split('\\');
  server = host;
  if (!port) {
    baseOptions.instanceName = instanceName;
  }
}

/**
 * Same server / login / pool sizing for every branch — only the target
 * database differs (see config/branches.js).
 */
function buildConfig(database) {
  return {
    server,
    port,
    database,
    user: mssqlEnv.user,
    password: mssqlEnv.password,
    options: { ...baseOptions },
    pool: {
      min: mssqlEnv.poolMin,
      max: mssqlEnv.poolMax,
      idleTimeoutMillis: 30000,
    },
    requestTimeout: mssqlEnv.requestTimeout,
    connectionTimeout: mssqlEnv.connectionTimeout,
  };
}

class MssqlConnection {
  constructor(database = mssqlEnv.database) {
    this.database = database;
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
    try {
      logger.info(`[BUSY ERP] Connecting to ${server}${port ? ':' + port : ''} / ${this.database}...`);
      this.pool = await new mssql.ConnectionPool(buildConfig(this.database)).connect();

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

// One MssqlConnection per database name, created lazily and reused.
const poolsByDatabase = new Map();

/** Returns a *connected* MssqlConnection for `database`, connecting on first use. */
async function poolForDatabase(database) {
  const key = database || mssqlEnv.database;
  let conn = poolsByDatabase.get(key);
  if (!conn) {
    conn = new MssqlConnection(key);
    poolsByDatabase.set(key, conn);
  }
  if (!conn.isConnected) {
    await conn.connect();
  }
  return conn;
}

// Back-compat singleton — the Turning Point / default database. Used by
// invoiceReport, receiptTotalsReport and the /sync/status route
// (mssqlDb.isConnected / .lastError). connect() is still called lazily by
// those callers.
const mssqlDb = new MssqlConnection();
poolsByDatabase.set(mssqlDb.database, mssqlDb);

module.exports = { MssqlConnection, mssqlDb, poolForDatabase, sql: mssql };
