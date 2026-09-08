/**
 * Minimal, dependency-free migration runner: creates the target database
 * if it doesn't exist, then runs every .sql file in migrations/ in
 * filename order. Each file is idempotent (CREATE TABLE IF NOT EXISTS),
 * so re-running this script is always safe.
 */
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const env = require('../config/env');
const logger = require('../config/logger');

async function run() {
  // First connect WITHOUT selecting a database, so we can create it.
  const bootstrapConn = await mysql.createConnection({
    host: env.db.host,
    port: env.db.port,
    user: env.db.user,
    password: env.db.password,
    multipleStatements: true,
  });

  try {
    logger.info(`Ensuring database "${env.db.database}" exists on ${env.db.host}:${env.db.port}...`);
    await bootstrapConn.query(
      `CREATE DATABASE IF NOT EXISTS \`${env.db.database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`
    );
  } finally {
    await bootstrapConn.end();
  }

  const conn = await mysql.createConnection({
    host: env.db.host,
    port: env.db.port,
    user: env.db.user,
    password: env.db.password,
    database: env.db.database,
    multipleStatements: true,
  });

  try {
    const migrationsDir = path.resolve(__dirname, 'migrations');
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

module.exports = { run };

if (require.main === module) {
  run()
    .then(() => process.exit(0))
    .catch((err) => {
      logger.error('Migration failed', { message: err.message, stack: err.stack });
      process.exit(1);
    });
}
