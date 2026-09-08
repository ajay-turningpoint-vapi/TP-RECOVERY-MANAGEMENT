import { CustomerReport } from '../reports/customer/customerReport.types';

/** Fields compared for value drift between BUSY and the MariaDB mirror. */
const COMPARED_FIELDS: (keyof CustomerReport)[] = [
  'ledgerClosingBalance',
  'lastInvoiceDate',
  'lastInvoiceAmount',
  'amountAlreadyDue',
  'futureDueAmount',
  'age0_30',
  'age31_60',
  'age61_90',
  'age90Plus',
  'creditDays',
  'creditLimit',
];

const MONEY_FIELDS = new Set<keyof CustomerReport>([
  'ledgerClosingBalance',
  'lastInvoiceAmount',
  'amountAlreadyDue',
  'futureDueAmount',
  'age0_30',
  'age31_60',
  'age61_90',
  'age90Plus',
  'creditLimit',
]);

// Anything within one paisa/cent is a rounding artifact, not a real drift.
const MONEY_TOLERANCE = 0.01;

export interface FieldDifference {
  customerId: number;
  field: keyof CustomerReport;
  busyValue: unknown;
  mariaDbValue: unknown;
}

export interface ComparisonResult {
  busyCount: number;
  mariaDbCount: number;
  missingInMariaDb: number[];
  extraInMariaDb: number[];
  differences: FieldDifference[];
  pass: boolean;
}

function normalizeDate(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  const d = v instanceof Date ? v : new Date(v as string);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 10); // date-only comparison — times aren't part of the contract
}

function normalizeString(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  return s === '' ? null : s;
}

function valuesDiffer(field: keyof CustomerReport, a: unknown, b: unknown): boolean {
  if (a === null && b === null) return false;
  if (a === null || b === null) return true;

  if (field.toLowerCase().includes('date')) {
    return normalizeDate(a) !== normalizeDate(b);
  }

  if (typeof a === 'number' || typeof b === 'number' || MONEY_FIELDS.has(field)) {
    const na = Number(a);
    const nb = Number(b);
    if (Number.isNaN(na) || Number.isNaN(nb)) return String(a) !== String(b);
    return Math.abs(na - nb) > MONEY_TOLERANCE;
  }

  return normalizeString(a) !== normalizeString(b);
}

/** Compares BUSY (source of truth) against the MariaDB mirror, matched by customerId. */
export function compareCustomerReports(
  busyRows: CustomerReport[],
  mariaDbRows: CustomerReport[]
): ComparisonResult {
  const busyById = new Map(busyRows.map((r) => [r.customerId, r]));
  const mariaDbById = new Map(mariaDbRows.map((r) => [r.customerId, r]));

  const missingInMariaDb: number[] = [];
  const extraInMariaDb: number[] = [];
  const differences: FieldDifference[] = [];

  for (const [customerId, busyRow] of busyById) {
    const mariaDbRow = mariaDbById.get(customerId);
    if (!mariaDbRow) {
      missingInMariaDb.push(customerId);
      continue;
    }
    for (const field of COMPARED_FIELDS) {
      if (valuesDiffer(field, busyRow[field], mariaDbRow[field])) {
        differences.push({
          customerId,
          field,
          busyValue: busyRow[field],
          mariaDbValue: mariaDbRow[field],
        });
      }
    }
  }

  for (const customerId of mariaDbById.keys()) {
    if (!busyById.has(customerId)) {
      extraInMariaDb.push(customerId);
    }
  }

  return {
    busyCount: busyRows.length,
    mariaDbCount: mariaDbRows.length,
    missingInMariaDb,
    extraInMariaDb,
    differences,
    pass: missingInMariaDb.length === 0 && extraInMariaDb.length === 0 && differences.length === 0,
  };
}

export function formatComparisonReport(result: ComparisonResult): string {
  const lines: string[] = [];
  lines.push('CUSTOMER REPORT VALIDATION');
  lines.push('==========================');
  lines.push('');
  lines.push(`BUSY records:       ${result.busyCount}`);
  lines.push(`MariaDB records:    ${result.mariaDbCount}`);
  lines.push('');
  lines.push(`Missing in MariaDB: ${result.missingInMariaDb.length}`);
  lines.push(`Extra in MariaDB:   ${result.extraInMariaDb.length}`);
  lines.push(`Different values:   ${result.differences.length}`);
  lines.push('');

  if (result.missingInMariaDb.length > 0) {
    lines.push(`Missing customer IDs: ${result.missingInMariaDb.slice(0, 20).join(', ')}`);
  }
  if (result.extraInMariaDb.length > 0) {
    lines.push(`Extra customer IDs: ${result.extraInMariaDb.slice(0, 20).join(', ')}`);
  }

  for (const diff of result.differences.slice(0, 20)) {
    lines.push('');
    lines.push(`Customer: ${diff.customerId}`);
    lines.push(`Field: ${diff.field}`);
    lines.push(`BUSY:     ${diff.busyValue}`);
    lines.push(`MariaDB:  ${diff.mariaDbValue}`);
  }
  if (result.differences.length > 20) {
    lines.push('');
    lines.push(`... and ${result.differences.length - 20} more difference(s).`);
  }

  lines.push('');
  lines.push(`STATUS: ${result.pass ? 'PASS' : 'FAIL'}`);

  return lines.join('\n');
}
