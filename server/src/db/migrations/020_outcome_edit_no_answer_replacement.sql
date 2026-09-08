-- Adds 'NoAnswerReplacement' to outcome_edit_requests.outcome_kind: the RE-
-- approval path for replacing a recorded No Answer once its same-day
-- self-service window has passed (see customerService.applyOutcome's
-- `replacingNoAnswer` and outcomeEditService.js's 'NoAnswerReplacement'
-- kind). Same day, the salesman replaces it directly with no approval —
-- past that day, it goes through this generic outcome-edit-request flow
-- like every other outcome kind already does.
--
-- ALTER ... MODIFY is safely re-runnable — matching migration
-- 019_ptp_pending_verification_status.sql's precedent for widening an enum.
ALTER TABLE outcome_edit_requests
  MODIFY COLUMN outcome_kind ENUM('PTP','PaymentClaim','Dispute','FollowUp','Simple','NoAnswerReplacement') NOT NULL;
