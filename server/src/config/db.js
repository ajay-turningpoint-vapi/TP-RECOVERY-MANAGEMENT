const mysql = require('mysql2/promise');
const env = require('./env');
const logger = require('./logger');

const pool = mysql.createPool({
  host: env.db.host,
  port: env.db.port,
  user: env.db.user,
  password: env.db.password,
  database: env.db.database,
  waitForConnections: true,
  connectionLimit: env.db.connectionLimit,
  queueLimit: 0,
  // DATE columns (as opposed to DATETIME) come back as plain 'YYYY-MM-DD'
  // strings instead of JS Date objects. mysql2 otherwise anchors DATE
  // values to local-timezone midnight while other drivers (e.g. the mssql
  // one BUSY sync data flows through) anchor to UTC midnight — a day's
  // drift in IST, proven to cause real false positives when this database
  // held only the RMS schema's own DATE columns wouldn't have surfaced,
  // but now that BUSY-sourced DATE columns (customers.last_receipt_date,
  // customer_ageing_snapshot.*) live here too, this must match the fix
  // already proven necessary for that data.
  dateStrings: ['DATE'],
  namedPlaceholders: true,
});

pool.on('connection', () => {
  logger.debug('New MariaDB connection established in pool');
});

/**
 * Run a query with automatic connection acquire/release via the pool.
 * Always use parameterized queries (? placeholders or :named with
 * namedPlaceholders) — never string-interpolate user input into SQL.
 */
async function query(sql, params) {
  const [rows] = await pool.query(sql, params);
  return rows;
}

/**
 * Run a callback within a single transaction. The callback receives a
 * connection to use for every statement in the transaction — never mix the
 * pool's `query()` with a transaction's own connection.
 */
async function withTransaction(callback) {
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

async function ping() {
  const connection = await pool.getConnection();
  try {
    await connection.query('SELECT 1');
  } finally {
    connection.release();
  }
}

async function closePool() {
  await pool.end();
}

module.exports = { pool, query, withTransaction, ping, closePool };
