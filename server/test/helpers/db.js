const env = require('../../src/config/env');
const { seed } = require('../../src/db/seed');
const { closePool } = require('../../src/config/db');

if (!env.isTest) {
  throw new Error(
    'Test helpers were loaded without NODE_ENV=test — refusing to run against a non-test database. Run tests via `npm test`.'
  );
}
if (!/test/i.test(env.db.database)) {
  throw new Error(
    `MARIADB_DATABASE ("${env.db.database}") doesn't look like a test database (expected a name containing "test"). ` +
      'Refusing to run — this guard exists so a misconfigured test run can never wipe real data.'
  );
}

/** Wipes and reloads the curated demo dataset — same data every test file starts from. */
async function resetDb() {
  await seed();
}

module.exports = { resetDb, closePool };
