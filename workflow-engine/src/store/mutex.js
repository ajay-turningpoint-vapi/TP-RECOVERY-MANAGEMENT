// Per-key async mutex. BullMQ workers can run job callbacks concurrently
// (any worker with `concurrency > 1`, or several worker processes) even
// though the store below is a single in-process object — two jobs
// touching the same customer at once is a real race without this.
//
// A real database replaces this with row-level locking / transactions;
// this is documented, removable scaffolding standing in for that until
// the DB exists.
const locks = new Map(); // key -> Promise chain tail

export async function withLock(key, fn) {
  const previous = locks.get(key) || Promise.resolve();
  let release;
  const current = new Promise((resolve) => {
    release = resolve;
  });
  locks.set(key, previous.then(() => current));

  await previous;
  try {
    return await fn();
  } finally {
    release();
    if (locks.get(key) === current) {
      locks.delete(key);
    }
  }
}
