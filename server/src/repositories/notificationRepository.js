const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

/**
 * A notification with userId = NULL is a broadcast — visible to everyone,
 * same idea as a system-wide announcement (the daily snapshot job raises
 * one of these). Its `is_read` column is a single flag shared by every
 * viewer, so a per-user "read" action can never touch it without also
 * clearing it for everyone else — a broadcast's real per-user read state
 * instead lives in notification_reads (see migrations/010), joined in
 * below as `readByViewer`. Per-user rows keep using `is_read` directly, so
 * only the broadcast branch needs the join.
 */
function mapNotification(row) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    severity: row.severity,
    title: row.title,
    body: row.body,
    customerId: row.customer_id,
    isRead: row.user_id === null ? !!row.read_by_viewer : !!row.is_read,
    createdAt: row.created_at,
  };
}

/** Per-user rows come first so a user's own notifications aren't buried under broadcasts. */
async function findForUser(userId) {
  const rows = await query(
    `SELECT n.*, (nr.notification_id IS NOT NULL) AS read_by_viewer
     FROM notifications n
     LEFT JOIN notification_reads nr ON nr.notification_id = n.id AND nr.user_id = :userId
     WHERE n.user_id = :userId OR n.user_id IS NULL
     ORDER BY (n.user_id IS NULL) ASC, n.created_at DESC`,
    { userId }
  );
  return rows.map(mapNotification);
}

async function findById(id, userId) {
  const rows = await query(
    `SELECT n.*, (nr.notification_id IS NOT NULL) AS read_by_viewer
     FROM notifications n
     LEFT JOIN notification_reads nr ON nr.notification_id = n.id AND nr.user_id = :userId
     WHERE n.id = :id LIMIT 1`,
    { id, userId: userId || null }
  );
  return mapNotification(rows[0]);
}

async function countUnread(userId) {
  const rows = await query(
    `SELECT COUNT(*) AS cnt FROM notifications n
     WHERE (n.user_id = :userId AND n.is_read = 0)
        OR (n.user_id IS NULL AND NOT EXISTS (
              SELECT 1 FROM notification_reads nr WHERE nr.notification_id = n.id AND nr.user_id = :userId
            ))`,
    { userId }
  );
  return rows[0].cnt;
}

async function insert(notification, connection) {
  const id = notification.id || uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO notifications (id, user_id, severity, title, body, customer_id)
     VALUES (:id, :userId, :severity, :title, :body, :customerId)`,
    {
      id,
      userId: notification.userId || null,
      severity: notification.severity || 'info',
      title: notification.title,
      body: notification.body,
      customerId: notification.customerId || null,
    }
  );
  return id;
}

/**
 * Marks a notification read for this one viewer. A per-user row (user_id =
 * userId) updates its own is_read directly. A broadcast row (user_id IS
 * NULL) instead records this viewer's read in notification_reads — its
 * is_read column stays 0 forever, since that column belongs to no single
 * viewer. The caller (notificationService.markRead) has already checked
 * this notification is actually visible to this user before calling here.
 */
async function markRead(id, userId) {
  await query('UPDATE notifications SET is_read = 1 WHERE id = :id AND user_id = :userId', { id, userId });
  await query(
    `INSERT IGNORE INTO notification_reads (notification_id, user_id)
     SELECT :id, :userId FROM notifications WHERE id = :id AND user_id IS NULL`,
    { id, userId }
  );
}

async function markAllReadForUser(userId) {
  await query('UPDATE notifications SET is_read = 1 WHERE user_id = :userId', { userId });
  await query(
    `INSERT IGNORE INTO notification_reads (notification_id, user_id)
     SELECT id, :userId FROM notifications WHERE user_id IS NULL`,
    { userId }
  );
}

module.exports = { mapNotification, findForUser, findById, countUnread, insert, markRead, markAllReadForUser };
