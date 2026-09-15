-- The RE can "mark complete" an underperforming-salesman nudge for the
-- day. It's recorded here per (salesman, date); the roster filters out
-- salesmen dismissed today. A new calendar day (or the salesman's
-- collection % rising above the threshold) brings them back automatically.
CREATE TABLE IF NOT EXISTS re_underperformance_dismissals (
  id             VARCHAR(36) PRIMARY KEY,
  salesman_id    VARCHAR(64) NOT NULL,
  dismissed_date DATE NOT NULL,
  dismissed_by   VARCHAR(64) NOT NULL,
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_salesman_date (salesman_id, dismissed_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
