const path = require('path');
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const env = require('./config/env');
const requestLogger = require('./middleware/requestLogger');
const { notFoundHandler, errorHandler } = require('./middleware/errorHandler');
const { apiLimiter } = require('./middleware/rateLimit');
const emitOnWrite = require('./middleware/emitOnWrite');
const routes = require('./routes');

/**
 * Production stays a strict whitelist (CORS_ORIGINS). Outside production —
 * local dev, `flutter run`/`flutter drive` — the web build's debug server
 * picks a different random localhost port every run, so a fixed whitelist
 * would need updating constantly. Reflect back any http(s)://localhost:*,
 * 127.0.0.1:*, or private-LAN-IP:* origin (so the web build can be served
 * on the machine's network address and opened from a phone/other device);
 * anything else still follows the explicit whitelist.
 */
function buildCorsOrigin() {
  if (env.isProduction) {
    return env.corsOrigins.length ? env.corsOrigins : false;
  }
  const localhostPattern = /^https?:\/\/(localhost|127\.0\.0\.1):\d+$/;
  // RFC 1918 private ranges: 10.x, 172.16–31.x, 192.168.x.
  const privateLanPattern = /^https?:\/\/(10(\.\d{1,3}){3}|172\.(1[6-9]|2\d|3[01])(\.\d{1,3}){2}|192\.168(\.\d{1,3}){2}):\d+$/;
  return (origin, callback) => {
    if (!origin || localhostPattern.test(origin) || privateLanPattern.test(origin) || env.corsOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(null, false);
    }
  };
}

function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  app.use(helmet());
  app.use(
    cors({
      origin: buildCorsOrigin(),
      credentials: true,
    })
  );
  // Chrome's Private Network Access checks require this on top of the usual
  // CORS headers before it'll let a page call a server on localhost/a
  // private IP — without it, the preflight is rejected entirely inside the
  // browser and the real request never reaches this server at all (no
  // error, no log line — confirmed while wiring up the Flutter web client).
  app.use((req, res, next) => {
    if (req.headers['access-control-request-private-network']) {
      res.setHeader('Access-Control-Allow-Private-Network', 'true');
    }
    next();
  });
  // compression() buffers/gzips the response body — fatal for the SSE
  // stream at /api/events, which must flush each event immediately.
  app.use(
    compression({
      filter: (req, res) => req.path !== '/api/events' && compression.filter(req, res),
    })
  );
  app.use(express.json({ limit: '2mb' }));
  app.use(requestLogger);
  app.use('/api', apiLimiter);
  // Fan a real-time "your lists changed" event to connected clients after
  // every successful mutating /api request (post-response, never blocks it).
  app.use('/api', emitOnWrite);

  // BUSY sync status/controls dashboard — a MANAGEMENT-gated static page;
  // its data calls go through /api/busy-sync/*, which enforce auth
  // themselves, so serving the shell here needs no extra guard.
  app.use('/busy-sync', express.static(path.join(__dirname, '..', 'public', 'busy-sync')));

  app.use(routes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

module.exports = createApp;
