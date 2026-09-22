-- Backs the offline write-queue's idempotency guard (see
-- middleware/idempotency.js): the Flutter client generates one UUID per
-- queued action and resends it as X-Idempotency-Key on every retry. If a
-- write actually committed server-side but the response was lost (network
-- drop between commit and ack), a retry with the same key replays the
-- original response instead of re-executing the mutation — so a flaky
-- connection can never double-record an outcome, double-create a PTP, etc.
CREATE TABLE IF NOT EXISTS idempotency_keys (
  `key` VARCHAR(64) NOT NULL,
  route VARCHAR(255) NOT NULL,
  status_code INT NOT NULL,
  response_body MEDIUMTEXT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
