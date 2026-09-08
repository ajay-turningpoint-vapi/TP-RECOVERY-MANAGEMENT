const rateLimit = require('express-rate-limit');
const { TooManyRequestsError } = require('../errors/AppError');
const env = require('../config/env');

function handler(req, res, next) {
  next(new TooManyRequestsError('Too many requests — please slow down and try again shortly.'));
}

// Applied to the whole API — generous enough for normal use, tight enough
// to blunt accidental retry storms or scripted abuse. Relaxed in plain
// `development` for the same reason as loginLimiter below: the growing
// Dart integration test suite issues far more than 300 req/min against
// the local dev server once several test files run together — confirmed
// by a real 429 on a live full `flutter test` run, not a guess.
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: env.isProduction || env.isTest ? 300 : 5000,
  standardHeaders: true,
  legacyHeaders: false,
  handler,
});

// Tighter limit specifically on login, keyed by IP — the classic place
// credential-stuffing / brute-force attempts land. Relaxed only in plain
// `development` (what pm2's dev server actually runs under) — the
// growing Dart integration test suite (multiple files, each logging in
// several times per run) legitimately exceeds 20 logins per 15 minutes
// against that server, confirmed by real 429s during a full `flutter
// test` run. `test` (this server's own test suite) stays strict so the
// "exceeding the limit returns 429" test keeps meaning something.
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: env.isProduction || env.isTest ? 20 : 500,
  standardHeaders: true,
  legacyHeaders: false,
  handler,
});

module.exports = { apiLimiter, loginLimiter };
