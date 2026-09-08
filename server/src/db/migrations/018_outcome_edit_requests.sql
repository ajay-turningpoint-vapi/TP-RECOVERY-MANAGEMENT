-- Generic "edit a recorded outcome" request, RE-approved before it applies.
-- A salesperson opens the outcome they already recorded (PTP / payment claim /
-- dispute / follow-up / a simple call outcome), edits its fields in place,
-- adds a reason, and submits. Nothing changes until a Recovery Executive
-- approves — on approve the requested_payload is applied to the underlying
-- artifact and its side effects are re-run. Generalises the PTP-only
-- correction pattern (ptps.correction_requested_*) to every outcome type.
--
-- src/db/migrate.js has no applied-migrations tracking, so every .sql file
-- re-runs on every migrate — CREATE TABLE IF NOT EXISTS makes this a no-op
-- on subsequent runs.
CREATE TABLE IF NOT EXISTS outcome_edit_requests (
  id                VARCHAR(36) NOT NULL PRIMARY KEY,
  customer_id       VARCHAR(36) NOT NULL,
  salesman_id       VARCHAR(36) NOT NULL,
  outcome_kind      ENUM('PTP','PaymentClaim','Dispute','FollowUp','Simple') NOT NULL,
  artifact_id       VARCHAR(36) NULL,
  original_payload  JSON NOT NULL,
  requested_payload JSON NOT NULL,
  edit_reason       VARCHAR(500) NOT NULL,
  status            ENUM('Pending','Approved','Rejected') NOT NULL DEFAULT 'Pending',
  rejection_reason  VARCHAR(255) NULL,
  requested_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at       DATETIME NULL,
  CONSTRAINT fk_outcome_edit_customer FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
  CONSTRAINT fk_outcome_edit_salesman FOREIGN KEY (salesman_id) REFERENCES users(id)     ON DELETE CASCADE,
  INDEX idx_outcome_edit_customer (customer_id),
  INDEX idx_outcome_edit_salesman (salesman_id),
  INDEX idx_outcome_edit_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
