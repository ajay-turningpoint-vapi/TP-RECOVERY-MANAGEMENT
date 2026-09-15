// Shared PARENTGRP filter builder for the BUSY MSSQL report queries
// (customerReport.mssql.sql, receiptTotalsReport.mssql.sql). Each query
// carries a `/*{{PARENTGRP_FILTER}}*/` placeholder; this turns a branch's
// code list (config/branches.js) into the `AND M.PARENTGRP IN (...)`
// clause. Codes are validated digits-only — they come from our own
// registry, but never interpolate anything unchecked into SQL.

// Turning Point group list — the default when no branch is passed, so a
// bare call keeps the historical single-branch behaviour.
const DEFAULT_PARENT_GROUPS = ['574140', '574141', '258335', '577533'];

function parentGroupClause(parentGroups) {
  const groups = (parentGroups && parentGroups.length ? parentGroups : DEFAULT_PARENT_GROUPS).map(String);
  const bad = groups.find((g) => !/^\d+$/.test(g));
  if (bad != null) {
    throw new Error(`Invalid PARENTGRP code "${bad}" — must be digits only`);
  }
  // Quoted — the column compares as text in this BUSY data; bare ints risk
  // an implicit-conversion error (proven against live data).
  return `AND M.PARENTGRP IN (${groups.map((g) => `'${g}'`).join(', ')})`;
}

module.exports = { parentGroupClause, DEFAULT_PARENT_GROUPS };
