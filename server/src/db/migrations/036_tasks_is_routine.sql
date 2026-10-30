-- Distinguishes a routine/nightly-refresh recovery call (silently
-- retargeted, never shown to the salesperson — "Start Recovery" already
-- covers it) from one driven by a specific event the salesperson needs to
-- know about right now (a payment claim rejected, a PTP broken, a dispute
-- decided, …). Both previously shared the same source='Recovery' string,
-- so the Flutter client had no way to tell "just the nightly sweep passed
-- through" apart from "RE just rejected your payment claim" and hid both
-- from the Tasks tab equally. Defaults to TRUE (routine) so every existing
-- row keeps today's behavior until recoveryTaskService explicitly marks a
-- fresh event-driven task/retarget as FALSE.
-- Guarded by information_schema: src/db/migrate.js re-runs every .sql
-- file on every migrate (no applied-migrations table), so this must be
-- safe to run more than once — same idiom as 017_add_due_days_to_invoice_snapshot.sql.
DROP PROCEDURE IF EXISTS _add_tasks_is_routine;

CREATE PROCEDURE _add_tasks_is_routine()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'tasks'
      AND COLUMN_NAME = 'is_routine'
  ) THEN
    ALTER TABLE tasks ADD COLUMN is_routine TINYINT(1) NOT NULL DEFAULT 1;
  END IF;
END;

CALL _add_tasks_is_routine();

DROP PROCEDURE _add_tasks_is_routine;
