-- INIT CUSTOMER INVOICE SNAPSHOT
CREATE TABLE IF NOT EXISTS customer_invoice_snapshot (
  ref_code              INT NOT NULL PRIMARY KEY,
  customer_id           INT NOT NULL,
  customer_name         VARCHAR(255) NOT NULL,
  invoice_date          DATETIME NOT NULL,
  due_date              DATETIME NOT NULL,
  invoice_no            VARCHAR(100) NOT NULL,
  ref_amount            DECIMAL(14,2) NOT NULL DEFAULT 0,
  pending_amount        DECIMAL(14,2) NOT NULL DEFAULT 0,
  message               VARCHAR(50) NOT NULL,
  
  last_synced_at        DATETIME NOT NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX idx_customer_id (customer_id),
  INDEX idx_last_synced_at (last_synced_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
