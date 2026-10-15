/**
 * Watches pm2's own event bus for tp-rms-api / tp-rms-worker crashing or
 * being restarted, and sends a real email (see config/mailer.js) the
 * moment it happens — not a log line nobody's watching.
 *
 * Runs as its own pm2 app (see ecosystem.config.js: 'tp-rms-crash-watcher')
 * so pm2 itself keeps IT alive too. One real limitation, stated plainly:
 * pm2's bus reports both an unexpected crash AND a deliberate
 * `pm2 restart`/`pm2 stop` as the same 'restart'/'exit' events — there is
 * no clean signal to tell them apart from here. Every email says exactly
 * which event/process/exit code fired so a manual restart is easy to spot
 * and shrug off, rather than silently missing a real crash to stay quiet
 * on manual restarts.
 */
const pm2 = require('pm2');
const logger = require('../config/logger');
const { sendAlertEmail } = require('../config/mailer');

const WATCHED_APPS = new Set(['tp-rms-api', 'tp-rms-worker']);
// A pm2 app that's been deliberately stopped sits in this status — an
// 'exit' event arriving in this state is the tail end of a `pm2 stop`,
// not a new crash to alert on again (the 'restart'/prior 'exit' already
// did, or there's nothing further to say for a deliberate stop).
const QUIET_STATUSES = new Set(['stopped']);

function describe(packet) {
  const p = packet.process || {};
  return {
    name: p.name,
    event: packet.event,
    status: p.status,
    pm_id: p.pm_id,
    restartTime: p.restart_time,
    exitCode: packet.data && packet.data.exit_code !== undefined ? packet.data.exit_code : undefined,
  };
}

async function handleEvent(packet) {
  const info = describe(packet);
  if (!WATCHED_APPS.has(info.name)) return;
  if (!['exit', 'restart', 'stop', 'error'].includes(packet.event)) return;
  if (packet.event === 'exit' && QUIET_STATUSES.has(info.status)) return;

  logger.warn('[crashWatcher] watched process event', info);

  const when = new Date().toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' });
  const subject = `⚠️ TP-RMS: ${info.name} ${packet.event} (restart #${info.restartTime ?? '?'})`;
  const text =
    `${info.name} reported a "${packet.event}" event at ${when} IST.\n\n` +
    `Status: ${info.status}\n` +
    `pm2 restart count: ${info.restartTime ?? 'unknown'}\n` +
    (info.exitCode !== undefined ? `Exit code: ${info.exitCode}\n` : '') +
    `\nIf this wasn't a deliberate "pm2 restart"/"pm2 stop" you ran yourself, the process likely crashed and pm2 auto-restarted it. Check logs: pm2 logs ${info.name}`;

  await sendAlertEmail({ subject, text });
}

function main() {
  pm2.connect((err) => {
    if (err) {
      logger.error('[crashWatcher] failed to connect to pm2', { message: err.message });
      process.exit(1);
    }
    pm2.launchBus((busErr, bus) => {
      if (busErr) {
        logger.error('[crashWatcher] failed to launch pm2 event bus', { message: busErr.message });
        process.exit(1);
      }
      logger.info('[crashWatcher] watching for crashes', { apps: [...WATCHED_APPS] });
      bus.on('process:event', (packet) => {
        handleEvent(packet).catch((e) => logger.error('[crashWatcher] handleEvent failed', { message: e.message }));
      });
    });
  });
}

main();
