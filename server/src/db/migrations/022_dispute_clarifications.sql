-- Back-and-forth clarification thread on a dispute. When the RE hits
-- "Need Info", their question is stored here and a task is created for the
-- salesperson (tasks.dispute_id links it back). The salesperson answers
-- from that task — the answer is appended here and the dispute flips back
-- to 'Pending Approval' so it re-enters the RE review queue. Repeatable.

CREATE TABLE IF NOT EXISTS dispute_messages (
  id           VARCHAR(36) PRIMARY KEY,
  dispute_id   VARCHAR(36) NOT NULL,
  author_id    VARCHAR(64) NOT NULL,
  author_name  VARCHAR(128) NOT NULL,
  author_role  VARCHAR(32) NOT NULL,   -- RECOVERY_EXECUTIVE | SALESPERSON | MANAGEMENT
  kind         VARCHAR(16) NOT NULL,   -- question | answer
  body         VARCHAR(2000) NOT NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_dispute_created (dispute_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Links a salesperson's "provide clarification" task back to its dispute.
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS dispute_id VARCHAR(36) NULL;
