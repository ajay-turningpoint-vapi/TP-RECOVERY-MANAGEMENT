/** Fields compared for value drift between BUSY and the MariaDB mirror. */
const COMPARED_FIELDS = [
  'ledgerClosingBalance',
  'lastReceiptDate',
  'lastReceiptAmount',
  'amountAlreadyDue',
  'futureDueAmount',
  'age0_30',
  'age31_60',
  'age61_90',
  'age90Plus',
  'creditDays',
  'creditLimit',
];

const MONEY_FIELDS = new Set([
  'ledgerClosingBalance',
  'lastReceiptAmount',
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

function normalizeDate(v) {
  if (v === null || v === undefined) return null;
  const d = v instanceof Date ? v : new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 10);
}

function normalizeString(v) {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  return s === '' ? null : s;
}

function valuesDiffer(field, a, b) {
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
function compareCustomerReports(busyRows, mariaDbRows) {
  const busyById = new Map(busyRows.map((r) => [r.customerId, r]));
  const mariaDbById = new Map(mariaDbRows.map((r) => [r.customerId, r]));

  const missingInMariaDb = [];
  const extraInMariaDb = [];
  const differences = [];

  for (const [customerId, busyRow] of busyById) {
    const mariaDbRow = mariaDbById.get(customerId);
    if (!mariaDbRow) {
      missingInMariaDb.push(customerId);
      continue;
    }
    for (const field of COMPARED_FIELDS) {
      if (valuesDiffer(field, busyRow[field], mariaDbRow[field])) {
        differences.push({ customerId, field, busyValue: busyRow[field], mariaDbValue: mariaDbRow[field] });
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

module.exports = { compareCustomerReports };
