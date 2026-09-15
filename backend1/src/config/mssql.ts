import mssql from 'mssql';
import dotenv from 'dotenv';
import { Request, Response, NextFunction } from 'express';
import logger from '../utils/logger';
import { Branch } from './branches';
dotenv.config();

/** Per-connection overrides — a branch on a different SQL Server sets some/all of these. */
export interface MssqlTarget {
  server?: string;
  port?: number;
  user?: string;
  password?: string;
  database?: string;
}

const rawDefaultServer = process.env.DB_SERVER || '0.0.0.0';
const defaultPort = process.env.DB_PORT ? parseInt(process.env.DB_PORT, 10) : undefined;

const sharedOptions: any = {
  encrypt: process.env.DB_ENCRYPT !== 'false',
  trustServerCertificate: process.env.DB_TRUST_SERVER_CERTIFICATE === 'true',
  enableArithAbort: true,
  useUTC: true,
};

const sharedPool = {
  min: process.env.DB_POOL_MIN ? parseInt(process.env.DB_POOL_MIN, 10) : 2,
  max: process.env.DB_POOL_MAX ? parseInt(process.env.DB_POOL_MAX, 10) : 20,
  idleTimeoutMillis: 30000,
};

const requestTimeout = process.env.DB_REQUEST_TIMEOUT
  ? parseInt(process.env.DB_REQUEST_TIMEOUT, 10)
  : 120000;
const connectionTimeout = process.env.DB_CONNECTION_TIMEOUT
  ? parseInt(process.env.DB_CONNECTION_TIMEOUT, 10)
  : 30000;

/**
 * Builds an mssql config from the shared DB_* defaults, overridden by
 * whatever a branch specifies. `host\INSTANCE` in the server string is
 * split the same way the original single-database config did it.
 */
function buildConfig(target: MssqlTarget): { config: mssql.config; label: string } {
  const rawServer = target.server || rawDefaultServer;
  const port = target.port ?? defaultPort;

  let server = rawServer;
  const options = { ...sharedOptions };
  if (rawServer.includes('\\')) {
    const [host, instanceName] = rawServer.split('\\');
    server = host;
    if (!port) {
      options.instanceName = instanceName;
    }
  }

  const database = target.database || process.env.DB_DATABASE || 'BusyComp0018_db12026';

  const config: mssql.config = {
    server,
    port,
    database,
    user: target.user || process.env.DB_USER || 'sa',
    password: target.password || process.env.DB_PASSWORD || '',
    options,
    pool: { ...sharedPool },
    requestTimeout,
    connectionTimeout,
  };

  return { config, label: `${server}${port ? ':' + port : ''}/${database}` };
}

/** Stable cache key for one physical connection target. */
function targetKey(target: MssqlTarget): string {
  const server = target.server || rawDefaultServer;
  const port = target.port ?? defaultPort ?? '';
  const user = target.user || process.env.DB_USER || 'sa';
  const database = target.database || process.env.DB_DATABASE || '';
  return `${server}:${port}:${user}:${database}`;
}

/**
 * One lazily-connected MSSQL connection pool, with its own connectivity
 * state so callers/health-checks can tell exactly which target is down.
 */
export class MssqlConnection {
  private pool: mssql.ConnectionPool | null = null;
  private _isConnected = false;
  private _lastError: string | null = null;
  private readonly config: mssql.config;
  private readonly label: string;
  private connecting: Promise<mssql.ConnectionPool> | null = null;

  constructor(target: MssqlTarget = {}) {
    const built = buildConfig(target);
    this.config = built.config;
    this.label = built.label;
  }

  public get isConnected(): boolean {
    return this._isConnected;
  }

  public get lastError(): string | null {
    return this._lastError;
  }

  public async connect(): Promise<mssql.ConnectionPool> {
    if (this.pool && this._isConnected) {
      return this.pool;
    }
    if (this.connecting) {
      return this.connecting;
    }

    this.connecting = (async () => {
      try {
        logger.info(`[ERP] Connecting to Busy ERP at ${this.label}...`);
        const pool = await new mssql.ConnectionPool(this.config).connect();

        pool.on('error', (err: Error) => {
          this._isConnected = false;
          this._lastError = err.message;
          logger.error(`[ERP] Connection pool error (${this.label}) — ERP went offline: ${err.message}`);
        });

        this.pool = pool;
        this._isConnected = true;
        this._lastError = null;
        logger.info(`[ERP] Busy MSSQL connected successfully (${this.label}).`);
        return pool;
      } catch (err: any) {
        this._isConnected = false;
        this._lastError = err.message || String(err);
        logger.error(`[ERP] Connection failed (${this.label}): ${this._lastError}`);
        throw err;
      } finally {
        this.connecting = null;
      }
    })();

    return this.connecting;
  }

  /** Returns a live pool, connecting on first use. Throws if the target is unreachable. */
  public async getPoolAsync(): Promise<mssql.ConnectionPool> {
    if (this.pool && this._isConnected) {
      return this.pool;
    }
    return this.connect();
  }

  /** Synchronous accessor — assumes connect() already succeeded (kept for back-compat). */
  public getPool(): mssql.ConnectionPool {
    if (!this.pool || !this._isConnected) {
      const errMsg = this._lastError
        ? `ERP service is offline (${this.label}). Last error: ${this._lastError}`
        : `ERP service is not connected (${this.label}). Ensure the Busy ERP system is running.`;
      logger.error('[ERP] getPool() blocked — ERP is offline. ' + errMsg);
      throw new Error(errMsg);
    }
    return this.pool;
  }
}

/**
 * Caches one MssqlConnection per physical target so every branch — even
 * ones on a different server — reuses a single pool.
 */
class MssqlPoolManager {
  private readonly pools = new Map<string, MssqlConnection>();

  getConnection(target: MssqlTarget): MssqlConnection {
    const key = targetKey(target);
    let conn = this.pools.get(key);
    if (!conn) {
      conn = new MssqlConnection(target);
      this.pools.set(key, conn);
    }
    return conn;
  }

  getForBranch(branch: Branch): MssqlConnection {
    return this.getConnection({
      server: branch.server,
      port: branch.port,
      user: branch.user,
      password: branch.password,
      database: branch.database,
    });
  }

  async getPoolForBranch(branch: Branch): Promise<mssql.ConnectionPool> {
    return this.getForBranch(branch).getPoolAsync();
  }
}

export const mssqlPoolManager = new MssqlPoolManager();

/**
 * The default connection, bound to the shared DB_* env values. Health
 * check, requireErpConnection and any legacy sync caller keep using this
 * exactly as before.
 */
export const mssqlDb = mssqlPoolManager.getConnection({});

/**
 * Express middleware — blocks routes when the default ERP target is
 * unreachable. Per-branch reads now come from the MariaDB mirror, so this
 * still guards the right thing (the live sync source).
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
