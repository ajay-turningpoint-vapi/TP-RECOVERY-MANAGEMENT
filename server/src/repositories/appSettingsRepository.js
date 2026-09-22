const { query } = require('../config/db');

async function get(key) {
  const rows = await query('SELECT `value` FROM app_settings WHERE `key` = :key', { key });
  return rows[0]?.value ?? null;
}

async function set(key, value, updatedBy) {
  await query(
    `INSERT INTO app_settings (\`key\`, \`value\`, updated_by)
     VALUES (:key, :value, :updatedBy)
     ON DUPLICATE KEY UPDATE \`value\` = :value, updated_by = :updatedBy`,
    { key, value, updatedBy: updatedBy || null }
  );
}

module.exports = { get, set };
