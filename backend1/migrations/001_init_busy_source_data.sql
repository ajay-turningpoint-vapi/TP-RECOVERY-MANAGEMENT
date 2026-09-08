-- BUSY_SOURCE_DATA: mirrors data pulled from the BUSY ERP (the source of
-- truth). Written only by the nightly sync engine (src/sync/) — every run
-- fully replaces the set of rows that currently match the source query
-- (upsert + sweep of anything that fell out of scope).

CREATE TABLE IF NOT EXISTS customer_ageing_snapshot (
  customer_id             INT NOT NULL PRIMARY KEY,       -- BUSY MASTER1.CODE
  customer_name           VARCHAR(255) NOT NULL,

  ledger_closing_balance  DECIMAL(14,2) NOT NULL DEFAULT 0,
  balance_type            ENUM('DR','CR','ZERO') NOT NULL,

  amount_already_due      DECIMAL(14,2) NOT NULL DEFAULT 0,
  future_due_amount       DECIMAL(14,2) NOT NULL DEFAULT 0,

  age_0_30                DECIMAL(14,2) NOT NULL DEFAULT 0,
  age_31_60               DECIMAL(14,2) NOT NULL DEFAULT 0,
  age_61_90               DECIMAL(14,2) NOT NULL DEFAULT 0,
  age_90_plus             DECIMAL(14,2) NOT NULL DEFAULT 0,

  max_days_overdue        INT NOT NULL DEFAULT 0,
  outstanding_status      VARCHAR(20) NOT NULL,

  last_invoice_date       DATE NULL,
  last_invoice_amount     DECIMAL(14,2) NULL,

  mobile                  VARCHAR(50) NOT NULL DEFAULT '',
  address                 VARCHAR(500) NOT NULL DEFAULT '',
  salesman                VARCHAR(255) NULL,
  salesman_code           INT NULL,

  credit_days             INT NOT NULL DEFAULT 0,
  credit_limit            DECIMAL(14,2) NOT NULL DEFAULT 0,

  last_synced_at          DATETIME NOT NULL,
  created_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  INDEX idx_salesman_code (salesman_code),
  INDEX idx_last_synced_at (last_synced_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS sync_runs (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  job_name        VARCHAR(100) NOT NULL DEFAULT 'customer_ageing',
  started_at      DATETIME NOT NULL,
  finished_at     DATETIME NULL,
  status          ENUM('running','success','failed') NOT NULL DEFAULT 'running',
  rows_fetched    INT NOT NULL DEFAULT 0,
  rows_upserted   INT NOT NULL DEFAULT 0,
  rows_deleted    INT NOT NULL DEFAULT 0,
  error_message   TEXT NULL,

  INDEX idx_job_status (job_name, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
