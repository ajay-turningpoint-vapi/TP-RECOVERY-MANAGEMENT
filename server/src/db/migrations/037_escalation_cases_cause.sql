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
ALTER TABLE escalation_cases
  ADD COLUMN cause ENUM('BrokenPTP', 'CustomerRefused', 'NonContact', 'Manual') NULL;
