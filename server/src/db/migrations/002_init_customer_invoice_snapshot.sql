-- customer_invoice_snapshot tracks the exact invoices from BUSY for each customer.
-- Replaced nightly by customerInvoiceSync.js via an upsert/sweep process.

CREATE TABLE IF NOT EXISTS customer_invoice_snapshot (
  ref_code VARCHAR(128) NOT NULL PRIMARY KEY,
  customer_id VARCHAR(128) NOT NULL,
  invoice_no VARCHAR(128) NOT NULL,
  invoice_date DATE,
  due_date DATE,
  ref_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  pending_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
  message VARCHAR(128),
  last_synced_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_invoice_customer (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
