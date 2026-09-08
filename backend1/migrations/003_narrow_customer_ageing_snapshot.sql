-- The BUSY query backing the sync was replaced with an updated version
-- that no longer sources these fields (see
-- src/reports/customer/customerReport.mssql.sql) — drop the columns so
-- the table can't hold stale/misleading data nobody is writing anymore.
-- outstanding_status is kept: it's still populated, just computed in
-- application code now instead of by the raw BUSY query.
-- Idempotent: MariaDB supports DROP COLUMN IF EXISTS.

ALTER TABLE customer_ageing_snapshot
  DROP COLUMN IF EXISTS opening_outstanding,
  DROP COLUMN IF EXISTS current_year_invoice_amount,
  DROP COLUMN IF EXISTS current_year_sales_return,
  DROP COLUMN IF EXISTS current_year_receipts,
  DROP COLUMN IF EXISTS last_receipt_date,
  DROP COLUMN IF EXISTS last_receipt_amount,
  DROP COLUMN IF EXISTS email,
  DROP COLUMN IF EXISTS as_of_date;
