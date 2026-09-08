/**
 * Runs each test file as its own `node --test <file>` child process, one at
 * a time. Two things forced this instead of the simpler `node --test test/`:
 *
 * 1. `node --test <directory>` reliably threw a bogus "Cannot find module"
 *    error on this Node build (v25.9.0) — passing individual file paths
 *    does not hit it.
 * 2. Even where directory/no-path discovery did work, Node's default test
 *    concurrency runs multiple files in parallel — and every file here
 *    shares one real MariaDB test database, reset in each file's own
 *    `before()` hook. Running in parallel meant one file's reset could
 *    wipe data out from under another file mid-test. Sequential, isolated
 *    processes avoid that entirely.
 */
const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const testDir = __dirname;
const files = fs
  .readdirSync(testDir)
  .filter((f) => f.endsWith('.test.js'))
  .sort()
  .map((f) => path.join(testDir, f));

let anyFailed = false;

for (const file of files) {
  console.log(`\n=== ${path.relative(process.cwd(), file)} ===`);
  const result = spawnSync(process.execPath, ['--test', file], { stdio: 'inherit', env: process.env });
  if (result.status !== 0) anyFailed = true;
}

if (anyFailed) {
  console.error('\nOne or more test files failed.');
  process.exit(1);
}
console.log('\nAll test files passed.');
