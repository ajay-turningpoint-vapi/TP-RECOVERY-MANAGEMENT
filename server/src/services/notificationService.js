const notificationRepository = require('../repositories/notificationRepository');
const { ForbiddenError, NotFoundError } = require('../errors/AppError');

async function listForUser(userId) {
  const [items, unreadCount] = await Promise.all([
    notificationRepository.findForUser(userId),
    notificationRepository.countUnread(userId),
  ]);
  return { items, unreadCount };
}

async function markRead(id, user) {
  const notification = await notificationRepository.findById(id, user.id);
  if (!notification) throw new NotFoundError('Notification');
  // userId === null is a broadcast — visible to (and markable by) everyone;
  // anything else must actually be this user's own notification.
  if (notification.userId !== null && notification.userId !== user.id) {
    throw new ForbiddenError('Cannot mark another user’s notification as read');
  }
  await notificationRepository.markRead(id, user.id);
  return notificationRepository.findById(id, user.id);
}

async function markAllRead(user) {
  await notificationRepository.markAllReadForUser(user.id);
  return listForUser(user.id);
}

/** Used internally by other services/jobs to create a notification — not exposed as a write route. */
async function create(notification, connection) {
  return notificationRepository.insert(notification, connection);
}

module.exports = { listForUser, markRead, markAllRead, create };
