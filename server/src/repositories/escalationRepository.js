const { v4: uuid } = require('uuid');
const { query } = require('../config/db');

function mapEscalation(row) {
  if (!row) return null;
  return {
    id: row.id,
    customerId: row.customer_id,
    level: row.level,
    reason: row.reason,
    plan: row.plan,
    ownerId: row.owner_id,
    deadline: row.deadline,
    moneyAtRisk: Number(row.money_at_risk),
    isOpen: !!row.is_open,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function findAll() {
  const rows = await query('SELECT * FROM escalation_cases ORDER BY created_at DESC');
  return rows.map(mapEscalation);
}

async function findOpen() {
  const rows = await query('SELECT * FROM escalation_cases WHERE is_open = 1 ORDER BY created_at DESC');
  return rows.map(mapEscalation);
}

async function findByCustomer(customerId) {
  const rows = await query('SELECT * FROM escalation_cases WHERE customer_id = :customerId ORDER BY created_at DESC', { customerId });
  return rows.map(mapEscalation);
}

async function findOpenByCustomer(customerId, connection) {
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  const result = await run('SELECT * FROM escalation_cases WHERE customer_id = :customerId AND is_open = 1', { customerId });
  const rows = connection ? result[0] : result;
  return rows.map(mapEscalation);
}

async function findById(id) {
  const rows = await query('SELECT * FROM escalation_cases WHERE id = :id LIMIT 1', { id });
  return mapEscalation(rows[0]);
}

async function insert(escalation, connection) {
  const id = escalation.id || uuid();
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(
    `INSERT INTO escalation_cases (id, customer_id, level, reason, plan, owner_id, deadline, money_at_risk, is_open)
     VALUES (:id, :customerId, :level, :reason, :plan, :ownerId, :deadline, :moneyAtRisk, :isOpen)`,
    {
      id,
      customerId: escalation.customerId,
      level: escalation.level,
      reason: escalation.reason,
      plan: escalation.plan || null,
      ownerId: escalation.ownerId || null,
      deadline: escalation.deadline || null,
      moneyAtRisk: escalation.moneyAtRisk || 0,
      isOpen: escalation.isOpen === undefined ? 1 : escalation.isOpen ? 1 : 0,
    }
  );
  return id;
}

const COLUMN_MAP = {
  level: 'level',
  reason: 'reason',
  plan: 'plan',
  ownerId: 'owner_id',
  deadline: 'deadline',
  moneyAtRisk: 'money_at_risk',
  isOpen: 'is_open',
};

async function update(id, fields, connection) {
  const keys = Object.keys(fields).filter((k) => COLUMN_MAP[k]);
  if (keys.length === 0) return;
  const setClause = keys.map((k) => `${COLUMN_MAP[k]} = :${k}`).join(', ');
  const run = connection ? (sql, params) => connection.query(sql, params) : query;
  await run(`UPDATE escalation_cases SET ${setClause} WHERE id = :id`, { ...fields, id });
}

module.exports = { mapEscalation, findAll, findOpen, findByCustomer, findOpenByCustomer, findById, insert, update };
