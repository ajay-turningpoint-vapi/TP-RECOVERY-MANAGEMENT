const { emitChange, RESOURCE_ALL } = require('../realtime/eventBus');

// After any successful mutating /api request, tell connected clients their
// lists may be stale. Coarse on purpose (see RESOURCE_ALL) — the client
// debounces and re-fetches only what it holds. Scope:
//   - a SALESPERSON's own write  → { userId } (they + every RE/Manager get it)
//   - an RE/Manager's write       → broadcast to all RE/Manager
//     (delivery to the specific affected salesman is handled by
//      decisionNotify.notifyDecision, which knows who that is)
//
// Paths that never change a client-held list are skipped.
const SKIP_PREFIXES = ['/auth', '/events', '/attachments', '/notifications', '/sync-status'];

function emitOnWrite(req, res, next) {
  const method = req.method.toUpperCase();
  if (method === 'GET' || method === 'HEAD' || method === 'OPTIONS') return next();
  if (SKIP_PREFIXES.some((p) => req.path === p || req.path.startsWith(`${p}/`))) return next();

  res.on('finish', () => {
    if (res.statusCode < 200 || res.statusCode >= 300) return;
    const user = req.user;
    const salesmanId = user && user.role === 'SALESPERSON' ? user.id : null;
    emitChange(RESOURCE_ALL, { salesmanId, reason: `${method} ${req.path}` });
  });
  next();
}

module.exports = emitOnWrite;
