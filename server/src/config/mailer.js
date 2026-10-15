const nodemailer = require('nodemailer');
const env = require('./env');
const logger = require('./logger');

let transporter = null;

function getTransporter() {
  if (!env.smtp.host || !env.smtp.user || !env.smtp.pass) return null;
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: env.smtp.host,
      port: env.smtp.port,
      secure: env.smtp.secure,
      auth: { user: env.smtp.user, pass: env.smtp.pass },
    });
  }
  return transporter;
}

/**
 * Sends a real email via the configured SMTP account. Never throws into
 * the caller — a failed alert must never crash the thing trying to alert
 * about a crash; it just logs. Returns true/false for whether it sent.
 */
async function sendAlertEmail({ subject, text, html }) {
  const t = getTransporter();
  if (!t || !env.alertEmailTo) {
    logger.warn('[mailer] SMTP/ALERT_EMAIL_TO not configured — skipping alert email', { subject });
    return false;
  }
  try {
    await t.sendMail({
      from: `TP-RMS Alerts <${env.smtp.user}>`,
      to: env.alertEmailTo,
      subject,
      text,
      html,
    });
    logger.info('[mailer] alert email sent', { subject, to: env.alertEmailTo });
    return true;
  } catch (err) {
    logger.error('[mailer] failed to send alert email', { subject, message: err.message });
    return false;
  }
}

module.exports = { sendAlertEmail };
