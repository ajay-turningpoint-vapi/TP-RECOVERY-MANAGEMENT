# TP-RMS Server

Production-structured Express + MariaDB backend for TP-RMS: centralized
error handling, structured (Winston) logging, health/readiness monitoring,
JWT auth with hashed passwords, and a service/repository layered
architecture covering customers, tasks, PTPs, disputes, payment claims,
and the salesmen roster.

## ⚠️ Connectivity note

This server was built and syntax/logic-verified from an environment that
**cannot reach `192.168.1.11` at all** (fails at the network layer,
`EHOSTUNREACH`, confirmed via `ping`/`nc`) — that sandbox has no route to
your LAN. Every piece that doesn't require the live database has been
exercised for real (see "What's been verified" below), but **the actual
migration run, seed run, and live DB queries have not been run against
your real MariaDB instance** and need to happen on your machine, which
*is* on that network.

## Setup

```bash
cd server
npm install
```

`.env` already exists with the credentials you provided
(`MARIADB_HOST=192.168.1.11`, etc.) — it is git-ignored (`server/.env` and
the root `.gitignore` both exclude it) and will never be committed.
**Consider rotating that MariaDB password**, since it was shared directly
in chat and is now part of this conversation's history/logs.

The server creates its own database (`MARIADB_DATABASE=tp_rms` in `.env`)
on the same MariaDB instance — it does **not** touch whatever tables
already exist in `busywmsv1`. Change `MARIADB_DATABASE` in `.env` if you'd
rather it live inside `busywmsv1` or elsewhere.

## Running it

```bash
npm run migrate   # creates the database + all tables (idempotent)
npm run seed      # loads the same demo dataset the Flutter app ships with
```

For local development:

```bash
npm run dev          # API server, nodemon auto-restart
npm run worker:dev   # background worker (notifications + daily snapshot), separate process
```

On boot both the server and worker ping the database (and the worker also
pings Redis) first and **refuse to start** if either is unreachable —
you'll see a clear `Could not reach MariaDB at startup` log line and a
non-zero exit code rather than a silently broken process.

### Running in production (pm2)

Two processes are managed by pm2 — the API server and the background
worker — defined in `ecosystem.config.js`. They're deliberately separate:
a slow or failing background job (notification delivery, the daily
snapshot) can never starve HTTP request handling, and either side can be
restarted independently.

```bash
npm install -g pm2      # if not already installed
pm2 start ecosystem.config.js --env production
pm2 status               # both processes, restart count, memory
pm2 logs                 # tail both processes' logs
pm2 logs tp-rms-api      # just the API
pm2 restart tp-rms-api   # zero-downtime-ish restart of one process
pm2 stop all / pm2 delete all

pm2 save                 # snapshot the current process list
pm2 startup              # generates the command to auto-start pm2 on machine boot
```

pm2 automatically restarts a crashed process (verified: killing the API
process with `kill -9` mid-run brought it back online in ~3 seconds, with
the restart counted in `pm2 status`) and caps restarts at 10 within a
short window so a genuinely broken deploy fails loud instead of
restart-looping forever. Logs go to `server/logs/pm2-*.log` (gitignored)
in addition to the app's own Winston `combined.log`/`error.log`.

This also requires **Redis** to be running and reachable at `REDIS_URL`
(defaults to `redis://127.0.0.1:6379`) — the worker process pings it at
startup the same way the API pings MariaDB.

## Demo login credentials (after `npm run seed`)

| Username | Password | Role |
|---|---|---|
| `rahul` | `1234` | SALESPERSON |
| `mahesh` | `1234` | SALESPERSON |
| `amit.re` | `1234` | RECOVERY_EXECUTIVE |
| `ramesh.re` | `1234` | RECOVERY_EXECUTIVE |
| `suresh.mgr` | `1234` | MANAGEMENT |

## API surface

All `/api/*` routes require `Authorization: Bearer <token>` (obtained from
`POST /api/auth/login`) except login itself. `GET /health` (liveness) and
`GET /health/ready` (readiness — actually pings the DB) need no auth.

- `POST /api/auth/login`, `GET /api/auth/me`
- `GET /api/customers`, `GET /api/customers/:id`
- `POST /api/customers/:id/record-outcome`
- `POST /api/customers/:id/take-control` / `/release-control` (RE only)
- `POST /api/customers/:id/reassign` (RE/Manager)
- `POST /api/customers/:id/management-instruction` (RE/Manager)
- `GET /api/tasks`
- `POST /api/tasks/:id/complete`
- `POST /api/tasks/:id/request-extension`
- `POST /api/tasks/:id/approve-edit` / `/reject-edit` (RE/Manager)
- `POST /api/tasks/:id/reassign` (RE/Manager)
- `GET /api/ptps`
- `POST /api/ptps/:id/request-correction`
- `POST /api/ptps/:id/approve-correction` / `/reject-correction` (RE/Manager)
- `GET /api/disputes` (RE/Manager)
- `POST /api/disputes/:id/approve` / `/reject` / `/request-info` (RE/Manager)
- `GET /api/payment-claims`
- `POST /api/payment-claims/:id/verify` (RE/Manager)
- `GET /api/salesmen` (RE/Manager)
- `GET /api/escalations`, `GET /api/escalations/customer/:customerId`
- `POST /api/escalations/customer/:customerId` (RE/Manager) — raise an
  escalation; bumps the customer's `escalationLevel` only if more severe
  than what's already recorded
- `POST /api/escalations/:id/resolve` (RE/Manager) — closes it; resets the
  customer to `escalationLevel: none` only if no other open case remains
- `GET /api/notifications` (returns `{ items, unreadCount }`)
- `POST /api/notifications/:id/read`, `POST /api/notifications/read-all`

Every error response has the shape `{ "error": { "code", "message",
"details"? }, "requestId" }`. Every response carries an `X-Request-Id`
header for correlating with server logs. The general API is rate-limited
(300 req/min); `/api/auth/login` specifically to 20 req/15min per IP.

## What's been verified (real, not assumed)

This has now been run for real against your live MariaDB (`127.0.0.1`)
and Redis, not just reviewed by hand:

- `npm run migrate` created the full schema; `npm run seed` loaded the
  demo dataset.
- Login, customer list/detail, escalation raise → customer badge update →
  queued notification delivered → escalation resolve → badge reset,
  role-based 403 on a salesperson attempting to raise an escalation — all
  exercised via real HTTP requests against the running server.
- The BullMQ worker: notification jobs processed end-to-end (API → queue
  → worker → DB row → API read), and the daily-snapshot job. **Found and
  fixed a real bug here**: BullMQ v5+ deprecated the `queue.add(...,
  {repeat})` pattern for recurring jobs — using it silently ran the job
  *immediately* (`delay: 0` in the raw Redis job record) instead of
  waiting for the cron match. Fixed by switching to
  `queue.upsertJobScheduler()`; reconfirmed via Redis that the job is now
  correctly scheduled for 17:00, not on boot.
- pm2 process management: both processes come up under
  `pm2 start ecosystem.config.js`, and `pm2` genuinely auto-restarts a
  killed process (`kill -9` on the API's pid → back online in ~3s, restart
  counted in `pm2 status`).
- Fail-fast startup, malformed-JSON handling, and the rest of the HTTP
  layer as described in earlier passes — all still hold.

## Deliberately out of scope / simplified for this pass

To keep this pass honest about what's real:

- **Flutter client is not wired to this API yet.** The app still uses its
  in-memory `AppStore`/`BusySimulator`. Pointing it at these endpoints
  (replacing Provider state with HTTP calls) is a separate, large piece
  of work — say the word if you want that next.
- **No call-log table** exists yet, so `callsDone` / a real
  `collectionAchievedPercent` aren't in the `/api/salesmen` response —
  they were demo-only numbers in the Dart simulator with no real source
  of truth server-side. Everything else in that response (customer count,
  total overdue, due-today PTPs, PTP kept %) is a real, live SQL
  aggregate, not a stored counter that can drift.
- **Credit-health scoring and the detailed recovery-score weighting
  formula** from the Dart demo aren't reproduced — elaborate
  simulated/derived pieces, not core workflow correctness. The 5 PM
  control batch job itself *is* now real (see below) — it's the scoring
  math specifically that's simplified.
- **File attachments** (PTP/dispute evidence photos) have no
  table/endpoint yet.

## Running the test suite

```bash
npm test
```

38 real integration tests under `server/test/`, run against an isolated
**`BusyRMS_test`** database on the same MariaDB instance (never your
`BusyRMS` dev/demo data) — `pretest` runs the migration against it, and
every test file wipes and reloads the seed dataset in its own `before()`
hook. The suite boots real instances of the app via `fetch()`, not
mocks — auth, RBAC on every domain, the transactional "supersede open
tasks" / "never leave money due with nothing open" guards, escalation
severity rules, and the BullMQ notification pipeline with a real worker
consuming a real (test-prefixed) Redis queue.

Two real bugs were caught and fixed while writing these tests, not
before:
1. **`disputeRoutes.js`** gated the entire router — including the
   read-only list — behind `authorize('RECOVERY_EXECUTIVE',
   'MANAGEMENT')`, making `disputeService.listForUser`'s
   salesperson-scoping logic dead code: a salesperson got a flat 403
   instead of their own scoped dispute list. Fixed to match the
   escalations route pattern (auth for everyone, role-gate only on the
   mutating actions).
2. **The "never leave money due with nothing open" guard checked only the
   `tasks` table**, never PTPs — despite its own audit message claiming
   "no other open task or active PTP." A customer with an active
   *scheduled* PTP and no other task would still get a redundant
   follow-up task auto-created. Added `ptpRepository.hasActivePtpForCustomer`
   and wired it into the guard; a test proving the PTP correctly
   suppresses the guard (and a second proving the guard fires when no
   PTP/task remains) is what caught this in the first place.

`node --test <directory>` reliably threw a bogus module-resolution error
on the Node build in this environment (v25.9.0) — passing individual
file paths doesn't hit it. `test/run.js` works around this (and avoids a
real DB race from Node's default parallel test-file execution against
one shared database) by spawning each `*.test.js` file as its own
`node --test <file>` child process, sequentially.
