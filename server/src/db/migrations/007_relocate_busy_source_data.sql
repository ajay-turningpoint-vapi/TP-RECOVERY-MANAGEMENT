-- Relocates customer_ageing_snapshot + sync_runs into the single main
-- database (previously a standalone BUSY_SOURCE_DATA database on the
-- ERP's LAN host — see server/src/busySync/migrations/001-003_*.sql,
-- now retired/folded into this one file). Exact final schema those 3
-- migrations converged to (001's base + 002's surviving `gstno` column,
-- everything else 002 added was dropped again by 003).
--
-- Still written only by the nightly sync engine (customerAgeingSync.js)
-- as its raw, disposable BUSY mirror / staging+audit layer — the live
-- app reads real customer data from `customers` instead (see
-- 006_customers_busy_fields.sql).

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

  -- Named last_receipt_* directly (not last_invoice_*, later renamed by
  -- migration 013) — this CREATE TABLE only ever fires once, on a
  -- genuinely fresh database, so it should create the final name up
  -- front rather than a name a later migration immediately renames away.
  last_receipt_date       DATE NULL,
  last_receipt_amount     DECIMAL(14,2) NULL,

  mobile                  VARCHAR(50) NOT NULL DEFAULT '',
  gstno                   VARCHAR(20) NOT NULL DEFAULT '',
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
