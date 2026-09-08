-- A broadcast notification (notifications.user_id IS NULL — e.g. the daily
-- snapshot job's "5 PM control snapshot complete") has exactly one is_read
-- column shared by every viewer, so no per-user action can ever set it
-- without clearing it for everyone else — markRead()/markAllReadForUser()
-- correctly refused to touch it. The result: broadcasts were permanently
-- unread for every user, forever, with the unread badge only ever growing
-- (confirmed live: one new broadcast per day from the snapshot job). This
-- table gives each user their own read marker for broadcast rows, without
-- disturbing the existing is_read column's meaning for per-user rows.
-- Explicit charset/collation: the database's own default collation
-- (utf8mb4_general_ci) differs from the one notifications/users actually
-- use (utf8mb4_uca1400_ai_ci, set explicitly back in 001_init.sql) — an FK
-- to a column of a different collation is rejected outright (errno 150),
-- so this must match those tables' columns exactly, not the database default.
CREATE TABLE IF NOT EXISTS notification_reads (
  notification_id VARCHAR(36) NOT NULL,
  user_id VARCHAR(36) NOT NULL,
  read_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (notification_id, user_id),
  CONSTRAINT fk_notification_reads_notification FOREIGN KEY (notification_id) REFERENCES notifications(id) ON DELETE CASCADE,
  CONSTRAINT fk_notification_reads_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci;
