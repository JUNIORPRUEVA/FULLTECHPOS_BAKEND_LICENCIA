const { pool } = require('../db/pool');

function selectBase() {
  return `
    SELECT sp.*, c.name AS company_name,
           cs.status AS subscription_status,
           l.license_key,
           p.name AS product_name,
           pr.code AS project_code
    FROM subscription_payments sp
    INNER JOIN companies c ON c.id = sp.company_id
    INNER JOIN company_subscriptions cs ON cs.id = sp.subscription_id
    LEFT JOIN licenses l ON l.id = sp.license_id
    LEFT JOIN products p ON p.id = sp.product_id
    LEFT JOIN projects pr ON pr.id = sp.project_id
  `;
}

async function list(filters = {}) {
  const { company_id, subscription_id, status, product_id, project_id, license_id, limit = 50, offset = 0 } = filters;
  const params = [];
  const where = [];

  for (const [field, value] of Object.entries({ company_id, subscription_id, status, product_id, project_id, license_id })) {
    if (!value) continue;
    params.push(value);
    where.push(`sp.${field} = $${params.length}`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total FROM subscription_payments sp ${whereSql}`,
    params
  );

  params.push(limit, offset);
  const rowsRes = await pool.query(
    `${selectBase()}
     ${whereSql}
     ORDER BY COALESCE(sp.paid_at, sp.recorded_at) DESC, sp.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total: totalRes.rows[0]?.total || 0, payments: rowsRes.rows };
}

async function getById(id, { client = pool } = {}) {
  const res = await client.query(`${selectBase()} WHERE sp.id = $1`, [id]);
  return res.rows[0] || null;
}

async function findByReference(subscriptionId, reference, { client = pool, forUpdate = false } = {}) {
  if (!reference) return null;
  if (forUpdate) {
    const baseRes = await client.query(
      'SELECT id FROM subscription_payments WHERE subscription_id = $1 AND reference = $2 FOR UPDATE',
      [subscriptionId, reference]
    );
    if (!baseRes.rows[0]) return null;
    return getById(baseRes.rows[0].id, { client });
  }

  const res = await client.query(
    `${selectBase()} WHERE sp.subscription_id = $1 AND sp.reference = $2`,
    [subscriptionId, reference]
  );
  return res.rows[0] || null;
}

async function create(input, { client = pool } = {}) {
  const res = await client.query(
    `INSERT INTO subscription_payments (
      company_id, subscription_id, product_id, project_id, license_id, amount,
      currency, status, payment_method, reference, notes, paid_at, recorded_at,
      recorded_by, gateway_payload
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,COALESCE($13, now()),$14,$15
    ) RETURNING *`,
    [
      input.company_id,
      input.subscription_id,
      input.product_id || null,
      input.project_id || null,
      input.license_id || null,
      input.amount,
      input.currency || 'DOP',
      input.status,
      input.payment_method || 'manual',
      input.reference || null,
      input.notes || null,
      input.paid_at || null,
      input.recorded_at || null,
      input.recorded_by || null,
      input.gateway_payload || {}
    ]
  );
  return getById(res.rows[0].id, { client });
}

module.exports = {
  list,
  getById,
  findByReference,
  create
};