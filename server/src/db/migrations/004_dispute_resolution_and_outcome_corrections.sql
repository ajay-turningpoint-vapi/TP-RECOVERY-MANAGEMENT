-- Real backends for two features that were previously local-only client
-- state with zero server persistence:
--
-- 1. Dispute Resolution Verification — a second-stage RE/Manager action on
--    an already-Approved dispute confirming whether the resolution genuinely
--    came through (money actually received) or the amount must return to
--    active recovery. 'Returned to Recovery' is a new terminal status.
ALTER TABLE disputes
  MODIFY COLUMN status ENUM('Pending Approval','Approved','Rejected','Need More Information','Awaiting Verification','Resolved','Returned to Recovery') NOT NULL DEFAULT 'Pending Approval';

-- 2. Outcome Correction Requests — a salesperson cannot silently rewrite an
--    already-recorded outcome; it goes through real RE approval, the same
--    pattern already used for PTP corrections.
CREATE TABLE IF NOT EXISTS outcome_correction_requests (
  id                  VARCHAR(36) PRIMARY KEY,
  customer_id         VARCHAR(36) NOT NULL,
  salesman_id         VARCHAR(36) NOT NULL,
  original_outcome    VARCHAR(64) NOT NULL,
  original_reason     VARCHAR(255) NOT NULL,
  requested_outcome   VARCHAR(64) NOT NULL,
  requested_reason    VARCHAR(255) NOT NULL,
  request_note        VARCHAR(500) NOT NULL,
  status              ENUM('Pending','Approved','Rejected') NOT NULL DEFAULT 'Pending',
  rejection_reason    VARCHAR(255),
  requested_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at         DATETIME,
  CONSTRAINT fk_outcome_correction_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  CONSTRAINT fk_outcome_correction_salesman FOREIGN KEY (salesman_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_outcome_correction_customer (customer_id),
  INDEX idx_outcome_correction_salesman (salesman_id),
  INDEX idx_outcome_correction_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
