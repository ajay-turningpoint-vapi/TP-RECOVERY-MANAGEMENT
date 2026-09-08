-- Snapshot the customer's outstanding position at the moment a PTP is
-- made, so the automated PTP maturity job (workers/ptpMaturityWorker.js,
-- runs 11:30 IST daily) can later ask "did the promised amount actually
-- come off the ledger?" by diffing this baseline against the current
-- (nightly-BUSY-synced) balance.
--
-- Mirrors disputes.total_due_at_raise (001_init.sql) — the same
-- balance-at-the-time-of-commitment pattern. Nullable so every
-- pre-existing scheduled PTP stays valid; the maturity job has an
-- explicit fallback (customers.last_receipt_date / last_receipt_amount)
-- for rows created before this migration.
--
-- ADD COLUMN IF NOT EXISTS: src/db/migrate.js has no applied-migrations
-- tracking, so every .sql file re-runs on every migrate — each must
-- tolerate running more than once (same idiom as 002_ptp_maturity.sql,
-- 006_customers_busy_fields.sql).
ALTER TABLE ptps
  ADD COLUMN IF NOT EXISTS total_due_at_promise         DECIMAL(14,2) NULL,
  ADD COLUMN IF NOT EXISTS total_outstanding_at_promise DECIMAL(14,2) NULL;
