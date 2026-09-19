-- dispute_messages.created_at was second-precision DATETIME with no
-- tiebreaker — two replies landing in the same wall-clock second (a real
-- case for a live RE <-> resolution-owner back-and-forth chat) sorted
-- arbitrarily instead of in the order they were actually sent. Bump to
-- millisecond precision AND add a monotonically increasing `seq` as the
-- real ORDER BY key, since even ms precision can still collide under load
-- and `id` is a random UUID that carries no ordering information.
ALTER TABLE dispute_messages
  MODIFY COLUMN created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3);

ALTER TABLE dispute_messages
  ADD COLUMN IF NOT EXISTS seq BIGINT AUTO_INCREMENT UNIQUE;
