import mssql from 'mssql';
import dotenv from 'dotenv';
import { Request, Response, NextFunction } from 'express';
import logger from '../utils/logger';
dotenv.config();

const rawServer = process.env.DB_SERVER || '0.0.0.0';
const port = process.env.DB_PORT ? parseInt(process.env.DB_PORT, 10) : undefined;

let server = rawServer;
const options: any = {
  encrypt: process.env.DB_ENCRYPT !== 'false',
  trustServerCertificate: process.env.DB_TRUST_SERVER_CERTIFICATE === 'true',
  enableArithAbort: true,
  useUTC: true,
};

// host\INSTANCE — when port is set, connect by host:port (typical for static ports)
if (rawServer.includes('\\')) {
  const [host, instanceName] = rawServer.split('\\');
  server = host;
  if (!port) {
    options.instanceName = instanceName;
  }
}

const config: mssql.config = {
  server,
  port,
  database: process.env.DB_DATABASE || 'BusyComp0018_db12026',
  user: process.env.DB_USER || 'sa',
  password: process.env.DB_PASSWORD || '',
  options,
  pool: {
    min: process.env.DB_POOL_MIN ? parseInt(process.env.DB_POOL_MIN, 10) : 2,
    max: process.env.DB_POOL_MAX ? parseInt(process.env.DB_POOL_MAX, 10) : 20,
    idleTimeoutMillis: 30000,
  },
  requestTimeout:    process.env.DB_REQUEST_TIMEOUT    ? parseInt(process.env.DB_REQUEST_TIMEOUT, 10)    : 120000,
  connectionTimeout: process.env.DB_CONNECTION_TIMEOUT ? parseInt(process.env.DB_CONNECTION_TIMEOUT, 10) : 30000,
};

export class MssqlConnection {
  private pool: mssql.ConnectionPool | null = null;
  private _isConnected: boolean = false;
  private _lastError: string | null = null;

  /** True only when the pool is alive */
  public get isConnected(): boolean {
    return this._isConnected;
  }

  /** Last connection error (surfaced to API callers) */
  public get lastError(): string | null {
    return this._lastError;
  }

  public async connect(): Promise<mssql.ConnectionPool> {
    try {
      logger.info(`[ERP] Connecting to Busy ERP at ${server}${port ? ':' + port : ''}...`);
      this.pool = await new mssql.ConnectionPool(config).connect();

      // Track pool-level errors (e.g. dropped connection mid-session)
      this.pool.on('error', (err: Error) => {
        this._isConnected = false;
        this._lastError = err.message;
        logger.error(`[ERP] Connection pool error — ERP went offline: ${err.message}`);
      });

      this._isConnected = true;
      this._lastError = null;
      logger.info('[ERP] Busy MSSQL connected successfully.');
      return this.pool;
    } catch (err: any) {
      this._isConnected = false;
      this._lastError = err.message || String(err);
      logger.error(`[ERP] Connection failed: ${this._lastError}`);
      logger.warn('Warning: Cannot connect to ERP system (' + (err.code || 'Timeout') + ').');
      logger.warn('Error: ' + (err.message || 'socket hang up'));
      throw err;
    }
  }

  public getPool(): mssql.ConnectionPool {
    if (!this.pool || !this._isConnected) {
      const errMsg = this._lastError
        ? 'ERP service is offline. Last error: ' + this._lastError
        : 'ERP service is not connected. Ensure the Busy ERP system is running.';
      logger.error('[ERP] getPool() blocked — ERP is offline. ' + errMsg);
      throw new Error(errMsg);
    }
    return this.pool;
  }
}

export const mssqlDb = new MssqlConnection();

/**
 * Express middleware — blocks all /api/sync/* routes when ERP is unreachable.
 * Logs the blocked attempt and returns HTTP 503 with a descriptive error.
 */
export const requireErpConnection = (req: Request, res: Response, next: NextFunction): void => {
  if (!mssqlDb.isConnected) {
    const reason = mssqlDb.lastError || 'socket hang up / Connection Timeout';
    logger.error(
      '[ERP Guard] Blocked ' + req.method + ' ' + req.path + ' — ERP service is offline. Reason: ' + reason
    );
    res.status(503).json({
      message: 'ERP Service Unavailable',
      detail: 'The Busy ERP system is not reachable. Please ensure it is running and the network is active.',
      reason,
      hint: 'Check ERP server at: ' + (process.env.DB_SERVER || 'configured DB_SERVER'),
    });
    return;
  }
  next();
};

export default mssqlDb;
