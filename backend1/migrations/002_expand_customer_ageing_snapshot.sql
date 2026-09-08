-- Expands customer_ageing_snapshot to hold every field the canonical
-- CustomerReport contract needs (src/reports/customer/customerReport.types.ts),
-- so the MariaDB mirror can serve the same full report BUSY does.
-- Idempotent: MariaDB supports ADD COLUMN IF NOT EXISTS.

ALTER TABLE customer_ageing_snapshot
  ADD COLUMN IF NOT EXISTS opening_outstanding        DECIMAL(14,2) NOT NULL DEFAULT 0 AFTER customer_name,
  ADD COLUMN IF NOT EXISTS current_year_invoice_amount DECIMAL(14,2) NOT NULL DEFAULT 0 AFTER opening_outstanding,
  ADD COLUMN IF NOT EXISTS current_year_sales_return   DECIMAL(14,2) NOT NULL DEFAULT 0 AFTER current_year_invoice_amount,
  ADD COLUMN IF NOT EXISTS current_year_receipts       DECIMAL(14,2) NOT NULL DEFAULT 0 AFTER current_year_sales_return,
  ADD COLUMN IF NOT EXISTS last_receipt_date           DATE NULL AFTER last_invoice_amount,
  ADD COLUMN IF NOT EXISTS last_receipt_amount         DECIMAL(14,2) NULL AFTER last_receipt_date,
  ADD COLUMN IF NOT EXISTS email                       VARCHAR(255) NOT NULL DEFAULT '' AFTER mobile,
  ADD COLUMN IF NOT EXISTS gstno                       VARCHAR(20) NOT NULL DEFAULT '' AFTER email,
  ADD COLUMN IF NOT EXISTS as_of_date                  DATE NULL AFTER credit_limit;
