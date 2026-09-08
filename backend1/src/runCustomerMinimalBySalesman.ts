/**
 * npm run customer-minimal-by-salesman -- --salesmanCode=N [--source=busy|mariadb] [--limit=N]
 *
 * All of one salesman's customers, projected down to just customer code,
 * customer name, ledger closing balance, and address — reuses the same
 * canonical CustomerReportRepository (and its salesmanCode filter) as
 * runCustomerReport.ts, just trims the output instead of duplicating the
 * query. Defaults to source=mariadb (the synced BUSY_SOURCE_DATA mirror).
 */
import 'dotenv/config';
import { closePool as closeMariaDbPool } from './config/mariadb';
import { MssqlCustomerReportRepository } from './reports/customer/mssqlCustomerReportRepository';
import { MariaDbCustomerReportRepository } from './reports/customer/mariaDbCustomerReportRepository';

function parseArgs(): { source: 'busy' | 'mariadb'; salesmanCode: number; limit?: number } {
  const args = process.argv.slice(2);
  let source: 'busy' | 'mariadb' = 'mariadb';
  let salesmanCode: number | undefined;
  let limit: number | undefined;

  for (const arg of args) {
    const [key, value] = arg.replace(/^--/, '').split('=');
    if (key === 'source' && (value === 'busy' || value === 'mariadb')) {
      source = value;
    } else if (key === 'salesmanCode' && value) {
      salesmanCode = parseInt(value, 10);
    } else if (key === 'limit' && value) {
      limit = parseInt(value, 10);
    }
  }

  if (salesmanCode == null) {
    throw new Error('--salesmanCode=N is required.');
  }

  return { source, salesmanCode, limit };
}

async function main() {
  const { source, salesmanCode, limit } = parseArgs();
  const repo = source === 'busy' ? new MssqlCustomerReportRepository() : new MariaDbCustomerReportRepository();

  const rows = await repo.getCustomers({ salesmanCode, limit });
  const minimal = rows.map((r) => ({
    CUSTOMER_ID: r.customerId,
    CUSTOMER_NAME: r.customerName,
    LEDGER_CLOSING_BALANCE: r.ledgerClosingBalance,
    ADDRESS: r.address,
  }));

  process.stdout.write(`Customers for salesman ${salesmanCode}: ${minimal.length}\n\n`);
  process.stdout.write(JSON.stringify(minimal, null, 2) + '\n');
}

main()
  .catch((err) => {
    console.error('customer-minimal-by-salesman failed:', err.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closeMariaDbPool().catch(() => {});
    process.exit(process.exitCode ?? 0);
  });
