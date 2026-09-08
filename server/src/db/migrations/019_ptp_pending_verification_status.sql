-- Adds 'pendingVerification' to ptps.status: the state a PTP sits in from
-- the moment its due date arrives until the 2-day BUSY-receipt grace period
-- has passed (see services/ptpVerificationService.js). Replaces the old
-- 11:30 IST "PTP Auto-Reconciliation" job's immediate next-day resolution.
--
-- ALTER ... MODIFY is safely re-runnable (unlike ADD COLUMN), matching
-- migration 002_ptp_maturity.sql's precedent for widening this same enum.
ALTER TABLE ptps
  MODIFY COLUMN status ENUM('scheduled','pendingVerification','kept','partiallyKept','broken','financialSyncPending')
  NOT NULL DEFAULT 'scheduled';
