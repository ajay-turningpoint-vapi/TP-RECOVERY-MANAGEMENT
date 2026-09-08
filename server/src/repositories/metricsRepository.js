const { query } = require('../config/db');

function mapSnapshot(row) {
  return {
    date: row.snapshot_date,
    avgRecoveryScore: Number(row.avg_recovery_score),
    ptpAmountTotal: Number(row.ptp_amount_total),
    brokenPtpCount: row.broken_ptp_count,
    collectionExpected: Number(row.collection_expected),
    collectionActual: Number(row.collection_actual),
    noFollowUpCount: row.no_follow_up_count,
  };
}

/** Real accumulated history, oldest first — however many days have genuinely been recorded so far. */
async function listRecent(limitDays) {
  const rows = await query('SELECT * FROM daily_metrics_snapshot ORDER BY snapshot_date DESC LIMIT :limitDays', { limitDays });
  return rows.map(mapSnapshot).reverse();
}

/** One row per real calendar day — re-running the snapshot the same day overwrites that day's row rather than duplicating it. */
async function upsertToday(metrics) {
  await query(
    `INSERT INTO daily_metrics_snapshot (snapshot_date, avg_recovery_score, ptp_amount_total, broken_ptp_count, collection_expected, collection_actual, no_follow_up_count)
     VALUES (CURDATE(), :avgRecoveryScore, :ptpAmountTotal, :brokenPtpCount, :collectionExpected, :collectionActual, :noFollowUpCount)
     ON DUPLICATE KEY UPDATE
       avg_recovery_score = VALUES(avg_recovery_score),
       ptp_amount_total = VALUES(ptp_amount_total),
       broken_ptp_count = VALUES(broken_ptp_count),
       collection_expected = VALUES(collection_expected),
       collection_actual = VALUES(collection_actual),
       no_follow_up_count = VALUES(no_follow_up_count)`,
    metrics
  );
}

module.exports = { listRecent, upsertToday };
