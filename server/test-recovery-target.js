const { getDashboard } = require('./src/services/reportService');
const targetRepository = require('./src/repositories/targetRepository');

async function run() {
  try {
    // mock targetRepository
    targetRepository.getCurrentMonthTarget = async () => 0.25;

    // mock dependencies
    const reportService = require('./src/services/reportService');
    const user = { role: 'SALESPERSON', id: 'rahul' };

    // We can't easily mock everything here because it relies on the real db connection
    // Let's run migrations and seed locally to test
  } catch (err) {
    console.error(err);
  }
}
run();
