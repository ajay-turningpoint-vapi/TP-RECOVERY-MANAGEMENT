import path from 'path';
import express from 'express';
import dotenv from 'dotenv';
import helmet from 'helmet';
import mssqlDb, { requireErpConnection } from './config/mssql';
import adminRoutes from './routes/adminRoutes';
import reportRoutes from './routes/reportRoutes';
import logger from './utils/logger';

dotenv.config();

const app = express();
app.use(
  helmet({
    // The dashboard is same-origin static HTML/CSS/JS with no inline
    // scripts/styles, so helmet's default CSP works as-is — no need to
    // relax it.
  })
);
app.use(express.json());

const PORT = process.env.PORT || 5001;

app.get('/health', requireErpConnection, (req, res) => {
  res.json({ status: 'ok', erpConnected: mssqlDb.isConnected });
});

app.use('/api/admin', adminRoutes);
app.use('/api/reports', reportRoutes);

// The sync status dashboard — served from the same origin as the API,
// so no CORS setup is needed.
app.use(express.static(path.join(__dirname, '../public')));

mssqlDb.connect().then(() => {
  app.listen(PORT, () => {
    logger.info(`busy-db-explore backend running on port ${PORT}`);
  });
}).catch((err) => {
  logger.error('Failed to establish MSSQL connection on startup.', err);
  app.listen(PORT, () => {
    logger.info(`busy-db-explore backend running on port ${PORT} (MSSQL offline)`);
  });
});
