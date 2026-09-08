-- Real historical trend data for the report charts that used to be
-- hardcoded zero-filled placeholders client-side. One real row per day,
-- written by the existing 5 PM daily snapshot job (src/workers/snapshotWorker.js)
-- alongside its existing reopen-guard pass. Trend endpoints return only
-- whatever rows genuinely exist — no backfill, no fabricated history.
CREATE TABLE IF NOT EXISTS daily_metrics_snapshot (
  snapshot_date       DATE NOT NULL PRIMARY KEY,
  avg_recovery_score  DECIMAL(5,2) NOT NULL DEFAULT 0,
  ptp_amount_total    DECIMAL(14,2) NOT NULL DEFAULT 0,
  broken_ptp_count    INT NOT NULL DEFAULT 0,
  collection_expected DECIMAL(14,2) NOT NULL DEFAULT 0,
  collection_actual   DECIMAL(14,2) NOT NULL DEFAULT 0,
  no_follow_up_count  INT NOT NULL DEFAULT 0,
  created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
