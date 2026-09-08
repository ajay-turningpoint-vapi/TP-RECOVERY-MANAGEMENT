/**
 * Minimal, dependency-free migration runner: creates BUSY_SOURCE_DATA if
 * it doesn't exist, then runs every .sql file in migrations/ in filename
 * order. Each file is idempotent (CREATE TABLE IF NOT EXISTS), so
 * re-running this script is always safe.
 */
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import mysql from 'mysql2/promise';
import logger from '../utils/logger';

const HOST = process.env.MARIADB_HOST || '';
const PORT = process.env.MARIADB_PORT ? parseInt(process.env.MARIADB_PORT, 10) : 3306;
const USER = process.env.MARIADB_USER || '';
const PASSWORD = process.env.MARIADB_PASSWORD || '';
const DATABASE = process.env.MARIADB_DATABASE || 'BUSY_SOURCE_DATA';

export async function run(): Promise<void> {
  // First connect WITHOUT selecting a database, so we can create it.
  const bootstrapConn = await mysql.createConnection({
    host: HOST,
    port: PORT,
    user: USER,
    password: PASSWORD,
    multipleStatements: true,
  });

  try {
    logger.info(`Ensuring database "${DATABASE}" exists on ${HOST}:${PORT}...`);
    await bootstrapConn.query(
      `CREATE DATABASE IF NOT EXISTS \`${DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
    );
  } finally {
    await bootstrapConn.end();
  }

  const conn = await mysql.createConnection({
    host: HOST,
    port: PORT,
    user: USER,
    password: PASSWORD,
    database: DATABASE,
    multipleStatements: true,
  });

  try {
    const migrationsDir = path.resolve(__dirname, '../../migrations');
    const files = fs
      .readdirSync(migrationsDir)
      .filter((f) => f.endsWith('.sql'))
      .sort();

    for (const file of files) {
      const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
      logger.info(`Applying migration: ${file}`);
      await conn.query(sql);
    }

    logger.info(`Migrations complete (${files.length} file(s) applied).`);
  } finally {
    await conn.end();
  }
}

if (require.main === module) {
  run()
    .then(() => process.exit(0))
    .catch((err) => {
      logger.error('Migration failed', { message: err.message, stack: err.stack });
      process.exit(1);
    });
}
