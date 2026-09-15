const { query, withTransaction } = require('../config/db');
const { hashPassword } = require('../utils/password');

// Every BUSY-sourced salesman account is created with this universal
// password so they can log in immediately; change per-account later as
// needed.
const DEFAULT_SALESMAN_PASSWORD = '1234';

/**
 * A human login name from the BUSY salesman name — lowercase, digits and
 * parenthetical bits (phone suffixes etc.) dropped, words joined by '.'.
 * "GOPAL" -> "gopal", "NILESH FURIA(90041...)" -> "nilesh.furia".
 * Falls back to the BUSY code when nothing usable is left.
 */
function usernameFromName(name, code) {
  const slug = String(name)
    .replace(/\([^)]*\)/g, ' ')
    .replace(/[0-9]/g, ' ')
    .trim()
    .toLowerCase()
    .split(/[^a-z]+/)
    .filter(Boolean)
    .join('.');
  return slug || `sm.${code}`;
}

/** Base salesperson rows — every real, derived roster figure (recovery score, collection %, task completion, etc.) is computed by salesmanService from real customers/ptps/tasks, not stored here. */
async function findAllSalespersons() {
  return query(
    `SELECT id, username, full_name AS fullName, branch, phone, busy_salesman_code AS busySalesmanCode FROM users WHERE role = 'SALESPERSON' ORDER BY full_name`
  );
}

/**
 * Build/refresh the SALESPERSON roster straight from the BUSY customer
 * ageing feed for one branch. Every customer row in that feed carries a
 * salesman name (`row.salesman`, from MASTER1.NAME) and code
 * (`row.salesmanCode`, from MASTER1.CODE) — the distinct (code, name)
 * pairs ARE the roster now; there are no separately-seeded salesman
 * accounts.
 *
 * BUSY salesman codes are globally unique across branches, so the match
 * key stays `busy_salesman_code`. The display name is stored WITH the
 * branch suffix (`GOPAL -TP`, `SAGAR -Claart`) so an "All Branches" view
 * can tell two same-named salesmen apart; the login username stays clean.
 *
 * Matched on `busy_salesman_code`:
 *   - unknown code -> INSERT a SALESPERSON row (branch = branch.label,
 *     full_name = name + suffix, universal default password '1234').
 *   - known code   -> refresh `full_name` / `branch` if they've drifted.
 *
 * Never deletes. Idempotent — safe to run on every sync.
 *
 * @param {Array} rows  CustomerReport-shaped rows for this branch
 * @param {{ key: string, label: string, nameSuffix: string }} branch
 */
async function upsertBusySalesmen(rows, branch = { key: 'tp', label: 'Turning Point', nameSuffix: ' -TP' }) {
  const nameByCode = new Map();
  for (const r of rows) {
    const code = r.salesmanCode;
    const name = (r.salesman || '').trim();
    if (code == null || !name) continue;
    if (!nameByCode.has(code)) nameByCode.set(code, name);
  }
  if (nameByCode.size === 0) return { created: 0, renamed: 0 };

  const defaultHash = await hashPassword(DEFAULT_SALESMAN_PASSWORD);
  const displayName = (name) => `${name}${branch.nameSuffix}`;

  return withTransaction(async (connection) => {
    const [existing] = await connection.query(
      "SELECT id, busy_salesman_code AS code, branch, full_name AS fullName FROM users WHERE role = 'SALESPERSON' AND busy_salesman_code IS NOT NULL"
    );
    const existingByCode = new Map(existing.map((e) => [e.code, e]));

    const [allUsers] = await connection.query('SELECT LOWER(username) AS u FROM users');
    const takenUsernames = new Set(allUsers.map((r) => r.u));

    let created = 0;
    let renamed = 0;
    for (const [code, name] of nameByCode) {
      const found = existingByCode.get(code);
      const wantName = displayName(name);
      if (!found) {
        // Friendly login name. Turning Point keeps the bare slug (gopal);
        // every other branch gets a branch-tagged one (sagar.claart) so
        // logins are visibly separate and can't collide with another
        // branch's same-named salesman. Last resort on a same-branch
        // clash: append the BUSY code.
        const slug = usernameFromName(name, code);
        let username = branch.key === 'tp' ? slug : `${slug}.${branch.key}`;
        if (takenUsernames.has(username)) username = `${username}.${code}`;
        takenUsernames.add(username);
        await connection.query(
          `INSERT INTO users (id, username, password_hash, role, full_name, branch, busy_salesman_code)
           VALUES (?, ?, ?, 'SALESPERSON', ?, ?, ?)`,
          [`busy-sm-${code}`, username, defaultHash, wantName, branch.label, code]
        );
        created += 1;
      } else if ((found.fullName || '') !== wantName || (found.branch || '') !== branch.label) {
        await connection.query('UPDATE users SET full_name = ?, branch = ? WHERE id = ?', [
          wantName,
          branch.label,
          found.id,
        ]);
        renamed += 1;
      }
    }
    return { created, renamed };
  });
}

module.exports = { findAllSalespersons, upsertBusySalesmen };
