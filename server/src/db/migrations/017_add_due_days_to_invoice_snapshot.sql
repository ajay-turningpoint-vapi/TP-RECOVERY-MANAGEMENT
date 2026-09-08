-- Adds due_days to customer_invoice_snapshot: DATEDIFF(DAY, DueDate, GETDATE())
-- as computed by BUSY at sync time — signed (positive = past due, negative =
-- not yet due). Lets Customer 360 → Invoices show a per-invoice "N days
-- overdue" pill instead of only the account-wide oldest-overdue figure.
--
-- Guarded by information_schema because src/db/migrate.js has no
-- applied-migrations tracking — every .sql file re-runs on every migrate,
-- so each must tolerate running more than once (same idiom as
-- 015_add_customer_name_to_invoice_snapshot.sql).
DROP PROCEDURE IF EXISTS _add_due_days_to_invoice_snapshot;

CREATE PROCEDURE _add_due_days_to_invoice_snapshot()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'customer_invoice_snapshot'
      AND COLUMN_NAME = 'due_days'
  ) THEN
    ALTER TABLE customer_invoice_snapshot
      ADD COLUMN due_days INT NULL AFTER due_date;
  END IF;
END;

CALL _add_due_days_to_invoice_snapshot();

DROP PROCEDURE _add_due_days_to_invoice_snapshot;
