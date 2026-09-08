-- TP-RMS core schema. Runs against the database named in MARIADB_DATABASE
-- (created if it doesn't exist by migrate.js). All tables InnoDB + utf8mb4.

CREATE TABLE IF NOT EXISTS users (
  id            VARCHAR(36)   NOT NULL PRIMARY KEY,
  username      VARCHAR(64)   NOT NULL UNIQUE,
  password_hash VARCHAR(255)  NOT NULL,
  role          ENUM('SALESPERSON','RECOVERY_EXECUTIVE','MANAGEMENT') NOT NULL,
  full_name     VARCHAR(128)  NOT NULL,
  designation   VARCHAR(128),
  branch        VARCHAR(64),
  phone         VARCHAR(32),
  recovery_score        INT DEFAULT 75,
  calls_target           INT DEFAULT 0,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS customers (
  id                      VARCHAR(36)  NOT NULL PRIMARY KEY,
  name                    VARCHAR(255) NOT NULL,
  contact_number          VARCHAR(32),
  alternate_contact_number VARCHAR(32),
  branch                  VARCHAR(64),
  assigned_salesman_id    VARCHAR(36),
  total_outstanding       DECIMAL(14,2) NOT NULL DEFAULT 0,
  total_due               DECIMAL(14,2) NOT NULL DEFAULT 0,
  oldest_overdue_days     INT NOT NULL DEFAULT 0,
  current_recovery_state  ENUM('Action Required','Waiting / Monitoring','RE Control') NOT NULL DEFAULT 'Action Required',
  primary_next_action     VARCHAR(64) NOT NULL DEFAULT 'CALL CUSTOMER',
  reason_for_action       VARCHAR(255) NOT NULL DEFAULT '',
  escalation_level        ENUM('none','L1','L2','L3','L4') NOT NULL DEFAULT 'none',
  has_valid_next_action   TINYINT(1) NOT NULL DEFAULT 1,
  owner_mapping_required  TINYINT(1) NOT NULL DEFAULT 0,
  credit_health_score     INT,
  disputed_amount         DECIMAL(14,2) NOT NULL DEFAULT 0,
  no_answer_attempts      INT NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_customers_salesman FOREIGN KEY (assigned_salesman_id) REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_customers_salesman (assigned_salesman_id),
  INDEX idx_customers_state (current_recovery_state),
  INDEX idx_customers_escalation (escalation_level)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS invoices (
  id            VARCHAR(36)  NOT NULL PRIMARY KEY,
  customer_id   VARCHAR(36)  NOT NULL,
  invoice_number VARCHAR(64) NOT NULL,
  amount        DECIMAL(14,2) NOT NULL,
  status        VARCHAR(32)  NOT NULL DEFAULT 'Due',
  due_date      DATE,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_invoices_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  INDEX idx_invoices_customer (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS tasks (
  id                VARCHAR(36) NOT NULL PRIMARY KEY,
  type              ENUM('customerCall','physicalVisit','disputeResolution','documentFollowUp','financialTeamFollowUp','customerDetailCorrection','paymentVerification','managementInstruction') NOT NULL,
  customer_id       VARCHAR(36) NOT NULL,
  owner_id          VARCHAR(36) NOT NULL,
  deadline          DATETIME NOT NULL,
  priority          VARCHAR(16) NOT NULL DEFAULT 'Normal',
  reason            VARCHAR(500) NOT NULL,
  status            ENUM('pending','inProgress','completed','completedAwaitingVerification','closed') NOT NULL DEFAULT 'pending',
  outcome           VARCHAR(500),
  approval_status   ENUM('Pending','Approved','Rejected'),
  pending_reason    VARCHAR(500),
  pending_deadline  DATETIME,
  pending_priority  VARCHAR(16),
  source            VARCHAR(64) NOT NULL DEFAULT 'System',
  completed_at      DATETIME,
  reviewed_by_re    TINYINT(1) NOT NULL DEFAULT 0,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_tasks_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  CONSTRAINT fk_tasks_owner FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE RESTRICT,
  INDEX idx_tasks_customer (customer_id),
  INDEX idx_tasks_owner (owner_id),
  INDEX idx_tasks_status (status),
  INDEX idx_tasks_deadline (deadline)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ptps (
  id                          VARCHAR(36) NOT NULL PRIMARY KEY,
  customer_id                 VARCHAR(36) NOT NULL,
  amount_promised              DECIMAL(14,2) NOT NULL,
  promise_date                 DATETIME NOT NULL,
  payment_mode                 VARCHAR(32) NOT NULL,
  status                       ENUM('scheduled','kept','broken','financialSyncPending') NOT NULL DEFAULT 'scheduled',
  correction_requested_amount  DECIMAL(14,2),
  correction_requested_date    DATETIME,
  correction_reason            VARCHAR(500),
  correction_status            ENUM('Pending','Approved','Rejected'),
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_ptps_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  INDEX idx_ptps_customer (customer_id),
  INDEX idx_ptps_status (status),
  INDEX idx_ptps_promise_date (promise_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS disputes (
  id                VARCHAR(36) NOT NULL PRIMARY KEY,
  customer_id       VARCHAR(36) NOT NULL,
  amount            DECIMAL(14,2) NOT NULL,
  total_due_at_raise DECIMAL(14,2) NOT NULL DEFAULT 0,
  reason            VARCHAR(500) NOT NULL,
  status            ENUM('Pending Approval','Approved','Rejected','Need More Information','Awaiting Verification','Resolved') NOT NULL DEFAULT 'Pending Approval',
  status_detail     VARCHAR(128),
  invoice_number    VARCHAR(64),
  priority          VARCHAR(16) NOT NULL DEFAULT 'Medium',
  resolution_owner  VARCHAR(36),
  rejection_reason  VARCHAR(500),
  info_request_note VARCHAR(500),
  raised_date       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_updated      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_disputes_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  CONSTRAINT fk_disputes_resolution_owner FOREIGN KEY (resolution_owner) REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_disputes_customer (customer_id),
  INDEX idx_disputes_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS escalation_cases (
  id            VARCHAR(36) NOT NULL PRIMARY KEY,
  customer_id   VARCHAR(36) NOT NULL,
  level         ENUM('L1','L2','L3','L4') NOT NULL,
  reason        VARCHAR(500) NOT NULL,
  plan          VARCHAR(500),
  owner_id      VARCHAR(36),
  deadline      DATETIME,
  money_at_risk DECIMAL(14,2) NOT NULL DEFAULT 0,
  is_open       TINYINT(1) NOT NULL DEFAULT 1,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_escalation_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  INDEX idx_escalation_customer (customer_id),
  INDEX idx_escalation_open (is_open)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS payment_claims (
  id          VARCHAR(36) NOT NULL PRIMARY KEY,
  customer_id VARCHAR(36) NOT NULL,
  amount      DECIMAL(14,2) NOT NULL,
  claim_date  DATE NOT NULL,
  reference   VARCHAR(255),
  status      ENUM('Awaiting Verification','Verified','Failed','Sync Pending') NOT NULL DEFAULT 'Awaiting Verification',
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_payment_claims_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  INDEX idx_payment_claims_customer (customer_id),
  INDEX idx_payment_claims_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The customer's single canonical activity log — every RE/salesperson/
-- system action that touches a customer writes one row here. This is the
-- backend equivalent of Customer.auditHistory in the Flutter model.
CREATE TABLE IF NOT EXISTS audit_events (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  customer_id     VARCHAR(36) NOT NULL,
  type            VARCHAR(64) NOT NULL,
  description     TEXT NOT NULL,
  actor           VARCHAR(128) NOT NULL,
  previous_state  VARCHAR(255),
  new_state       VARCHAR(255),
  source          VARCHAR(64) NOT NULL DEFAULT 'App',
  occurred_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_audit_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  INDEX idx_audit_customer_time (customer_id, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS notifications (
  id          VARCHAR(36) NOT NULL PRIMARY KEY,
  user_id     VARCHAR(36),
  severity    ENUM('info','warning','critical') NOT NULL DEFAULT 'info',
  title       VARCHAR(255) NOT NULL,
  body        VARCHAR(500) NOT NULL,
  customer_id VARCHAR(36),
  is_read     TINYINT(1) NOT NULL DEFAULT 0,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_notifications_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
  INDEX idx_notifications_user (user_id, is_read)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
