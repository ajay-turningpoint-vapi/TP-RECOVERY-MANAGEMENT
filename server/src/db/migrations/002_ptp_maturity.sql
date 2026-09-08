-- PTP maturity: real manual reconciliation of a Scheduled PTP into
-- Kept/Partially Kept/Broken. There is no live BUSY/payment-gateway
-- integration to auto-detect this, so — exactly like Payment Already Made
-- claims elsewhere in this schema — it's a real action RE records after
-- genuinely checking with accounts/BUSY, not an automatic simulation.
ALTER TABLE ptps
  MODIFY COLUMN status ENUM('scheduled','kept','partiallyKept','broken','financialSyncPending') NOT NULL DEFAULT 'scheduled',
  ADD COLUMN IF NOT EXISTS amount_received DECIMAL(14,2) NULL,
  ADD COLUMN IF NOT EXISTS broken_reason VARCHAR(255) NULL;
