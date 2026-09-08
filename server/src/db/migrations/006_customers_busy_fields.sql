-- Adds BUSY-sourced columns to `customers` so real BUSY ERP data becomes
-- the RMS customer base (single-database consolidation). Reused existing
-- columns (total_outstanding, total_due, oldest_overdue_days,
-- contact_number, name) carry the equivalent BUSY fields directly —
-- these are only the genuinely new concepts.
--
-- Column ownership: only the BUSY sync (customerAgeingSync.js) ever
-- writes these columns. Every RMS action (record outcome, escalate,
-- dispute, take control) writes only the pre-existing workflow columns
-- via customerRepository.update()'s COLUMN_MAP allowlist, which never
-- included these — so the two write paths can never collide.
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS future_due_amount    DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS age_0_30             DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS age_31_60            DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS age_61_90            DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS age_90_plus          DECIMAL(14,2) NOT NULL DEFAULT 0,
  -- Named last_receipt_* (not last_invoice_*) since migration 013 renamed
  -- it — this file re-runs on every migrate invocation (no applied-
  -- migrations tracking table, see migrate.js), so it must create the
  -- final name directly rather than the original one 013 later renames
  -- away, or it would keep silently re-adding the old column every run.
  ADD COLUMN IF NOT EXISTS last_receipt_date    DATE NULL,
  ADD COLUMN IF NOT EXISTS last_receipt_amount  DECIMAL(14,2) NULL,
  ADD COLUMN IF NOT EXISTS credit_limit         DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS credit_days          INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gst_no               VARCHAR(20) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS address              VARCHAR(500) NULL,
  ADD COLUMN IF NOT EXISTS salesman             VARCHAR(255) NULL,
  ADD COLUMN IF NOT EXISTS busy_salesman_code   INT NULL,
  ADD COLUMN IF NOT EXISTS busy_last_synced_at  DATETIME NULL,
  ADD COLUMN IF NOT EXISTS busy_still_active    TINYINT(1) NOT NULL DEFAULT 1,
  ADD INDEX IF NOT EXISTS idx_customers_busy_salesman_code (busy_salesman_code),
  ADD INDEX IF NOT EXISTS idx_customers_busy_still_active (busy_still_active);
