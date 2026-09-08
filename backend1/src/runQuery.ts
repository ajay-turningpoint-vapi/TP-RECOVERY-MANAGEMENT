import fs from 'fs';
import path from 'path';
import mssqlDb from './config/mssql';

async function main() {
  await mssqlDb.connect();

  const query = fs.readFileSync(path.join(__dirname, '../../query.sql'), 'utf8');
  const pool = mssqlDb.getPool();

  try {
    const result = await pool.request().query(query);
    console.log(`\nRows returned: ${result.recordset.length}\n`);
    console.log(JSON.stringify(result.recordset, null, 2));
  } catch (err: any) {
    console.error('QUERY FAILED:', err.message);
  } finally {
    await pool.close();
    process.exit(0);
  }
}

main().catch((err) => {
  console.error('CONNECTION FAILED:', err.message);
  process.exit(1);
});
