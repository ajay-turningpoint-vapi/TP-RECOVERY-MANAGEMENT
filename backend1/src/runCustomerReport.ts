/**
 * npm run customer-report -- --source=busy|mariadb|both [--limit=N] [--salesmanCode=N]
 *
 * source=busy    — live BUSY (MSSQL) via MssqlCustomerReportRepository
 * source=mariadb — the synced mirror via MariaDbCustomerReportRepository
 * source=both    — runs both and validates them against each other
 *                   (compareCustomerReports), printing a PASS/FAIL report
 *                   and exiting non-zero on FAIL — for post-sync CI checks.
 *
 * --salesmanCode=N restricts to that one salesman's customers on either
 * side (CustomerReport.salesmanCode) — e.g.
 * `npm run customer-report -- --source=mariadb --salesmanCode=633582`.
 */
import 'dotenv/config';
import { closePool as closeMariaDbPool } from './config/mariadb';
import { MssqlCustomerReportRepository } from './reports/customer/mssqlCustomerReportRepository';
import { MariaDbCustomerReportRepository } from './reports/customer/mariaDbCustomerReportRepository';
import { CustomerReportOptions } from './reports/customer/customerReport.types';
import { compareCustomerReports, formatComparisonReport } from './validation/customerReportComparator';

function parseArgs(): { source: 'busy' | 'mariadb' | 'both' } & CustomerReportOptions {
  const args = process.argv.slice(2);
  let source: 'busy' | 'mariadb' | 'both' = 'both';
  let limit: number | undefined;
  let salesmanCode: number | undefined;

  for (const arg of args) {
    const [key, value] = arg.replace(/^--/, '').split('=');
    if (key === 'source' && (value === 'busy' || value === 'mariadb' || value === 'both')) {
      source = value;
    } else if (key === 'limit' && value) {
      limit = parseInt(value, 10);
    } else if (key === 'salesmanCode' && value) {
      salesmanCode = parseInt(value, 10);
    }
  }

  return { source, limit, salesmanCode };
}

async function main() {
  const { source, limit, salesmanCode } = parseArgs();
  const options: CustomerReportOptions = { limit, salesmanCode };
  const mssqlRepo = new MssqlCustomerReportRepository();
  const mariaDbRepo = new MariaDbCustomerReportRepository();

  if (source === 'busy') {
    const rows = await mssqlRepo.getCustomers(options);
    process.stdout.write(JSON.stringify(rows, null, 2) + '\n');
    return;
  }

  if (source === 'mariadb') {
    const rows = await mariaDbRepo.getCustomers(options);
    process.stdout.write(JSON.stringify(rows, null, 2) + '\n');
    return;
  }

  // source === 'both': fetch from each, compare, print a PASS/FAIL report.
  const [busyRows, mariaDbRows] = await Promise.all([
    mssqlRepo.getCustomers(options),
    mariaDbRepo.getCustomers(options),
  ]);
  const result = compareCustomerReports(busyRows, mariaDbRows);
  process.stdout.write(formatComparisonReport(result) + '\n');
  process.exitCode = result.pass ? 0 : 1;
}

main()
  .catch((err) => {
    console.error('customer-report failed:', err.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    // The mssql pool is torn down by process exit; we only own the
    // MariaDB pool here, so close it explicitly.
    await closeMariaDbPool().catch(() => {});
    process.exit(process.exitCode ?? 0);
  });
