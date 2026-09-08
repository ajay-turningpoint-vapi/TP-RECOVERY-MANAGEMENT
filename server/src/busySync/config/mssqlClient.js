const mssql = require('mssql');
const logger = require('../../config/logger');
const { mssql: mssqlEnv } = require('./env');

const rawServer = mssqlEnv.server || '0.0.0.0';
const port = mssqlEnv.port;

let server = rawServer;
const options = {
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
    options.instanceName = instanceName;
  }
}

const config = {
  server,
  port,
  database: mssqlEnv.database,
  user: mssqlEnv.user,
  password: mssqlEnv.password,
  options,
  pool: {
    min: mssqlEnv.poolMin,
    max: mssqlEnv.poolMax,
    idleTimeoutMillis: 30000,
  },
  requestTimeout: mssqlEnv.requestTimeout,
  connectionTimeout: mssqlEnv.connectionTimeout,
};

class MssqlConnection {
  constructor() {
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
      logger.info(`[BUSY ERP] Connecting to ${server}${port ? ':' + port : ''}...`);
      this.pool = await new mssql.ConnectionPool(config).connect();

      this.pool.on('error', (err) => {
        this._isConnected = false;
        this._lastError = err.message;
        logger.error(`[BUSY ERP] Connection pool error — ERP went offline: ${err.message}`);
      });

      this._isConnected = true;
      this._lastError = null;
      logger.info('[BUSY ERP] Connected successfully.');
      return this.pool;
    } catch (err) {
      this._isConnected = false;
      this._lastError = err.message || String(err);
      logger.error(`[BUSY ERP] Connection failed: ${this._lastError}`);
      throw err;
    }
  }

  getPool() {
    if (!this.pool || !this._isConnected) {
      const errMsg = this._lastError
        ? 'BUSY ERP is offline. Last error: ' + this._lastError
        : 'BUSY ERP is not connected.';
      throw new Error(errMsg);
    }
    return this.pool;
  }
}

const mssqlDb = new MssqlConnection();

module.exports = { MssqlConnection, mssqlDb, sql: mssql };
