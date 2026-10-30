-- Tags *why* an escalation was raised, distinct from the free-text
-- `reason` string. Four different things raise an escalation onto the
-- same customers.escalation_level badge (broken-PTP count, Customer
-- Refused, non-contact, and manual RE/management raises) — without this,
-- a pass that wants to auto-lower/resolve an escalation when its cause
-- clears (e.g. ptpService.reconcileBrokenPtpEscalation, see
-- services/ptpVerificationService.js's reverifyStalePtps) can't tell
-- whether the customer's currently-open case was actually caused by that
-- or by one of the other three. Nullable — every existing row stays NULL
-- ("unknown/legacy"), which the cause-filtered logic treats as never
-- eligible for auto-touch, so no pre-existing escalation's behavior
-- changes.
-- Guarded by information_schema: src/db/migrate.js re-runs every .sql
-- file on every migrate (no applied-migrations table), so this must be
-- safe to run more than once — same idiom as 017_add_due_days_to_invoice_snapshot.sql.
DROP PROCEDURE IF EXISTS _add_escalation_cases_cause;

CREATE PROCEDURE _add_escalation_cases_cause()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'escalation_cases'
      AND COLUMN_NAME = 'cause'
  ) THEN
    ALTER TABLE escalation_cases
      ADD COLUMN cause ENUM('BrokenPTP', 'CustomerRefused', 'NonContact', 'Manual') NULL;
  END IF;
END;

CALL _add_escalation_cases_cause();

DROP PROCEDURE _add_escalation_cases_cause;
