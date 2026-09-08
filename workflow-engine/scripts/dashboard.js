// Dev-only visual inspector for live queues/jobs (Bull Board). Not required
// for tests — just `npm run dashboard`, then open http://localhost:3131
// while `npm start` or `npm run smoke` is running against the same Redis.
import express from 'express';
import { createBullBoard } from '@bull-board/api';
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter';
import { ExpressAdapter } from '@bull-board/express';
import { allQueues } from '../src/queues/index.js';

const app = express();
const serverAdapter = new ExpressAdapter();
serverAdapter.setBasePath('/');

createBullBoard({
  queues: allQueues().map((q) => new BullMQAdapter(q)),
  serverAdapter,
});

app.use('/', serverAdapter.getRouter());

const port = process.env.DASHBOARD_PORT || 3131;
app.listen(port, () => {
  console.log(`Bull Board dashboard: http://localhost:${port}`);
});
