-- Guarded by information_schema: src/db/migrate.js re-runs every .sql
-- file on every migrate (no applied-migrations table), so this must be
-- safe to run more than once — same idiom as 017_add_due_days_to_invoice_snapshot.sql.
DROP PROCEDURE IF EXISTS _add_ptps_advance_amount;

CREATE PROCEDURE _add_ptps_advance_amount()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'ptps'
      AND COLUMN_NAME = 'advance_amount'
  ) THEN
    ALTER TABLE ptps ADD COLUMN advance_amount DECIMAL(14, 2) NULL;
  END IF;
END;

CALL _add_ptps_advance_amount();

DROP PROCEDURE _add_ptps_advance_amount;
