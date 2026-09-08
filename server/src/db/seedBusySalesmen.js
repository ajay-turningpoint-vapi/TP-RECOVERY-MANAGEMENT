/**
 * Syncs one SALESPERSON login account per distinct salesman_code found in
 * customer_ageing_snapshot (already synced by the daily BUSY sync).
 * Idempotent — re-running updates existing mappings (username, name)
 * rather than duplicating accounts.
 *
 * Username = the salesman's BUSY name, slugified, no code suffix (matches
 * the existing demo-account convention — rahul/1234, mahesh/1234).
 * Password is fixed to '1234' for every account (same convention as the
 * demo RE/Management accounts in seed.js) — reset to '1234' on every run,
 * so a salesman who forgets it can always be told the same fixed value
 * rather than needing a new password generated and redistributed.
 */
const { v4: uuid } = require('uuid');
const { query, closePool } = require('../config/db');
const { hashPassword } = require('../utils/password');
const logger = require('../config/logger');

const FIXED_PASSWORD = '1234';

function slugify(name) {
  const base = String(name || 'salesman')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '.')
    .replace(/^\.+|\.+$/g, '');
  return base || 'salesman';
}

/** Appends -2, -3, ... only if the plain slug is already taken by a different salesman_code — most names in this dataset are unique, so most usernames stay a clean plain name. */
async function resolveUniqueUsername(baseUsername, code) {
  let candidate = baseUsername;
  let suffix = 2;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const clashes = await query(
      'SELECT id FROM users WHERE username = :username AND (busy_salesman_code IS NULL OR busy_salesman_code != :code)',
      { username: candidate, code }
    );
    if (clashes.length === 0) return candidate;
    candidate = `${baseUsername}${suffix}`;
    suffix += 1;
  }
}

async function run() {
  // salesman_code = 0 (distinct from NULL) shows up for rows BUSY couldn't
  // resolve a real salesman for — not an account to create a login for.
  const salesmen = await query(
    'SELECT DISTINCT salesman_code, salesman FROM customer_ageing_snapshot WHERE salesman_code IS NOT NULL AND salesman_code != 0 ORDER BY salesman'
  );

  if (salesmen.length === 0) {
    logger.warn('No salesmen found in customer_ageing_snapshot — run a BUSY sync first.');
    return;
  }

  const passwordHash = await hashPassword(FIXED_PASSWORD);
  const accounts = [];

  for (const { salesman_code: code, salesman: name } of salesmen) {
    const username = await resolveUniqueUsername(slugify(name), code);
    const existing = await query('SELECT id, username FROM users WHERE busy_salesman_code = :code LIMIT 1', { code });

    if (existing.length > 0) {
      await query('UPDATE users SET username = :username, full_name = :name, password_hash = :passwordHash WHERE id = :id', {
        username,
        name: name || username,
        passwordHash,
        id: existing[0].id,
      });
    } else {
      await query(
        `INSERT INTO users (id, username, password_hash, role, full_name, busy_salesman_code)
         VALUES (:id, :username, :passwordHash, 'SALESPERSON', :fullName, :code)`,
        { id: uuid(), username, passwordHash, fullName: name || username, code }
      );
    }

    accounts.push({ code, name, username });
  }

  logger.info(`BUSY salesmen: ${salesmen.length} account(s) synced, all passwords set to "${FIXED_PASSWORD}".`);

  console.log('\n=== SALESMAN LOGIN CREDENTIALS (password is "1234" for all) ===\n');
  for (const a of accounts) {
    console.log(`  ${a.username}  /  1234   (${a.name}, code ${a.code})`);
  }
  console.log('\n=================================================================\n');
}

module.exports = { run };

if (require.main === module) {
  run()
    .then(() => closePool())
    .then(() => process.exit(0))
    .catch((err) => {
      logger.error('seedBusySalesmen failed', { message: err.message, stack: err.stack });
      process.exit(1);
    });
}
