# TP-RMS Workflow Engine

The real recovery-management workflow engine for TP-RMS, built on **BullMQ**
in plain JavaScript. No database yet — an in-memory store (`src/store/`)
stands in for it, isolated behind a single repository module so the future
API/DB layer only has to change one file. Every workflow that exists in the
Flutter app's `AppStore` (and a few the spec requires but the Dart app never
implemented — see comments in the processors) is here as real BullMQ
queues, workers, and jobs.

## Requirements

- Node.js ≥ 18
- A local Redis (BullMQ requires real Redis — not a mock)

## Setup

```bash
npm install
redis-server --daemonize yes   # or: docker compose up -d
cp .env.example .env           # optional — sensible defaults work as-is
```

## Running

```bash
npm start        # boots every worker + the two repeatable schedulers
npm run smoke     # runs one full realistic scenario across all 3 roles
                   # against real Redis and prints a human-readable trace
npm run dashboard  # Bull Board at http://localhost:3131 (dev-only, optional)
```

## Testing

```bash
npm test
```

Every test runs real Workers and real Queues against a real local Redis
(an isolated DB index — `REDIS_TEST_DB`, default `1` — flushed before each
test), not a mock. `scripts/check-redis.js` fails fast with a clear message
if Redis isn't reachable before the suite even starts.

- `test/*-lifecycle.test.js`, `test/escalation.test.js`, `test/dispute.test.js`,
  etc. — one file per workflow domain.
- `test/retry-backoff.test.js`, `rate-limit.test.js`, `stalled-job-recovery.test.js`,
  `graceful-shutdown.test.js`, `dead-letter.test.js`, `idempotency.test.js`,
  `priority.test.js`, `delayed-jobs.test.js`, `repeatable-jobs.test.js` —
  one file per BullMQ production edge case, each proven with real timing,
  real crashes/disconnects, and real Redis state — not simulated in a mock.

## Architecture

- `src/store/` — the in-memory "database." `repository.js` is the only
  seam that should need to change when a real DB is added.
- `src/queues/`, `src/workers/`, `src/processors/` — one of each per
  workflow domain (recovery-outcome, busy-sync, escalation, payment-claim,
  dispute, task, management-instruction, customer-reassignment,
  correction-request, five-pm-control) plus a shared `dead-letter` queue.
- `src/simulators/busy-client.js` — stands in for the real BUSY financial
  API, with configurable latency/failure-rate so retry/backoff/rate-limit
  behavior can be proven against realistic failure conditions, not just the
  happy path.
- `src/schedulers/register-repeatables.js` — the two spec-mandated
  recurring jobs (BUSY sync, 5 PM Control), registered via BullMQ's current
  `upsertJobScheduler` API (idempotent by id — safe to call on every boot).

See the code comments in `src/processors/*.js` for the specific gaps found
in the source Dart app (via a full workflow audit) that this engine closes
rather than replicates — e.g. BUSY-sync-outage gating that only covered
half the payment-claim flow, a dispute lifecycle that stopped at
Approved/Rejected instead of reaching Resolved, and task completion that
never re-checked whether money was still due.

## A production bug this session's own testing caught

The busy-sync → escalation Flow (`src/processors/busy-sync.processor.js`)
originally deadlocked in a real run (not any unit test) because its
`FlowProducer` parent job lived on the same single-concurrency `busy-sync`
queue as the job awaiting it. A second, subtler bug surfaced once that was
fixed: a `QueueEvents` subscription created lazily right before a
`waitUntilFinished` call can lose the race against a job that completes in
under a millisecond, silently hanging forever. Both are fixed with comments
explaining why, and both now have regression tests
(`test/escalation.test.js`'s "regression: a real busy-sync tick..." test,
and the pre-warmed `QueueEvents` pattern used throughout
`test/helpers.js`'s `addAndWait`). Found via `npm run smoke`, not the unit
suite — a reminder that a full realistic run is worth doing even when
every domain test is green.
