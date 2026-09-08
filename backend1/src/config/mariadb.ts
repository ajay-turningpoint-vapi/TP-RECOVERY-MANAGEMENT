import mysql from 'mysql2/promise';
import logger from '../utils/logger';

const pool = mysql.createPool({
  host: process.env.MARIADB_HOST,
  port: process.env.MARIADB_PORT ? parseInt(process.env.MARIADB_PORT, 10) : 3306,
  user: process.env.MARIADB_USER,
  password: process.env.MARIADB_PASSWORD,
  database: process.env.MARIADB_DATABASE || 'BUSY_SOURCE_DATA',
  waitForConnections: true,
  connectionLimit: process.env.MARIADB_CONNECTION_LIMIT
    ? parseInt(process.env.MARIADB_CONNECTION_LIMIT, 10)
    : 10,
  queueLimit: 0,
  namedPlaceholders: true,
  // DATE columns (as opposed to DATETIME) come back as plain 'YYYY-MM-DD'
  // strings instead of JS Date objects. mysql2 otherwise anchors DATE
  // values to local-timezone midnight while the mssql driver anchors
  // BUSY's dates to UTC midnight — a full day's drift in IST that showed
  // up as false positives in the BUSY-vs-MariaDB comparator. Reading
  // plain date strings and parsing them as UTC midnight ourselves
  // (see reports/customer/mariaDbCustomerReportRepository.ts) sidesteps
  // the ambiguity entirely.
  dateStrings: ['DATE'],
});

pool.on('connection', () => {
  logger.debug('[BUSY_SOURCE_DATA] New MariaDB connection established in pool');
});

async function query<T = any>(sql: string, params?: any): Promise<T> {
  const [rows] = await pool.query(sql, params);
  return rows as T;
}

async function withTransaction<T>(
  callback: (connection: mysql.PoolConnection) => Promise<T>
): Promise<T> {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const result = await callback(connection);
    await connection.commit();
    return result;
  } catch (err) {
    await connection.rollback();
    throw err;
  } finally {
    connection.release();
  }
}

async function ping(): Promise<void> {
  const connection = await pool.getConnection();
  try {
    await connection.query('SELECT 1');
  } finally {
    connection.release();
  }
}

async function closePool(): Promise<void> {
  await pool.end();
}

export default { pool, query, withTransaction, ping, closePool };
export { pool, query, withTransaction, ping, closePool };
