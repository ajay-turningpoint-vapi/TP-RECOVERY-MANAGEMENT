-- Adds customer_name to customer_invoice_snapshot so the synced BUSY
-- invoice rows carry the party name alongside customer_id (= BUSY
-- MASTER1.Code, the same value stored in customers.id). Customer 360
-- filters invoices with `WHERE customer_id = :id` where :id is the
-- customer's mastercode, so the name is only for display.
--
-- Guarded by information_schema because src/db/migrate.js has no
-- applied-migrations tracking — every .sql file re-runs on every
-- migrate, so each must tolerate running more than once.
DROP PROCEDURE IF EXISTS _add_customer_name_to_invoice_snapshot;

CREATE PROCEDURE _add_customer_name_to_invoice_snapshot()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'customer_invoice_snapshot'
      AND COLUMN_NAME = 'customer_name'
  ) THEN
    ALTER TABLE customer_invoice_snapshot
      ADD COLUMN customer_name VARCHAR(255) NULL AFTER customer_id;
  END IF;
END;

CALL _add_customer_name_to_invoice_snapshot();

DROP PROCEDURE _add_customer_name_to_invoice_snapshot;
