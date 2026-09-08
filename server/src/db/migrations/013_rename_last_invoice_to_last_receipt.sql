-- Renames last_invoice_date/last_invoice_amount to last_receipt_date/
-- last_receipt_amount on both tables that hold them. This is paired with
-- a real logic fix in customerReport.mssql.sql: the source query used to
-- compute the customer's last INVOICE (VCHTYPE=9, a sales voucher), not
-- their last RECEIPT/payment (VCHTYPE IN (14,3), TYPE=2) — the column was
-- misnamed relative to what the business actually needed here, which is
-- "when did this customer last pay us", not "when did we last bill them".
--
-- Guarded by information_schema (not a plain CHANGE COLUMN) because this
-- migration runner (src/db/migrate.js) has no applied-migrations tracking
-- table — every .sql file re-runs on every `npm run migrate` / pretest,
-- so each one must tolerate being run more than once. A plain
-- `CHANGE COLUMN last_invoice_date ...` errors with "Unknown column
-- 'last_invoice_date'" the second time, once it's already renamed.
DROP PROCEDURE IF EXISTS _rename_last_invoice_to_last_receipt;

CREATE PROCEDURE _rename_last_invoice_to_last_receipt()
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'customer_ageing_snapshot' AND COLUMN_NAME = 'last_invoice_date'
  ) THEN
    ALTER TABLE customer_ageing_snapshot
      CHANGE COLUMN last_invoice_date   last_receipt_date   DATE NULL,
      CHANGE COLUMN last_invoice_amount last_receipt_amount DECIMAL(14,2) NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'customers' AND COLUMN_NAME = 'last_invoice_date'
  ) THEN
    ALTER TABLE customers
      CHANGE COLUMN last_invoice_date   last_receipt_date   DATE NULL,
      CHANGE COLUMN last_invoice_amount last_receipt_amount DECIMAL(14,2) NULL;
  END IF;
END;

CALL _rename_last_invoice_to_last_receipt();

DROP PROCEDURE _rename_last_invoice_to_last_receipt;
