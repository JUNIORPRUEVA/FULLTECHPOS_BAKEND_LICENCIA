const { pool } = require('../db/pool');

function selectBase() {
  return `
    SELECT cs.*, c.name AS company_name,
           pp.code AS plan_code, pp.name AS plan_name, pp.billing_period,
           p.slug AS product_slug, p.name AS product_name,
           pr.code AS project_code, pr.name AS project_name
    FROM company_subscriptions cs
    INNER JOIN companies c ON c.id = cs.company_id
    INNER JOIN product_plans pp ON pp.id = cs.plan_id
    LEFT JOIN products p ON p.id = cs.product_id
    LEFT JOIN projects pr ON pr.id = cs.project_id
  `;
}

async function list(filters = {}) {
  const { company_id, status, product_id, project_id, plan_id, limit = 50, offset = 0 } = filters;
  const params = [];
  const where = [];

  for (const [field, value] of Object.entries({ company_id, status, product_id, project_id, plan_id })) {
    if (!value) continue;
    params.push(value);
    where.push(`cs.${field} = $${params.length}`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total FROM company_subscriptions cs ${whereSql}`,
    params
  );

  params.push(limit, offset);
  const rowsRes = await pool.query(
    `${selectBase()}
     ${whereSql}
     ORDER BY cs.updated_at DESC, cs.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total: totalRes.rows[0]?.total || 0, subscriptions: rowsRes.rows };
}

async function getById(id, { client = pool, forUpdate = false } = {}) {
  if (forUpdate) {
    const baseRes = await client.query('SELECT * FROM company_subscriptions WHERE id = $1 FOR UPDATE', [id]);
    if (!baseRes.rows[0]) return null;
  }

  const res = await client.query(`${selectBase()} WHERE cs.id = $1`, [id]);
  return res.rows[0] || null;
}

async function create(input, { client = pool } = {}) {
  const res = await client.query(
    `INSERT INTO company_subscriptions (
      company_id, product_id, project_id, plan_id, status, start_date, end_date,
      renewal_date, grace_until, cancelled_at, suspended_at, notes, metadata,
      created_by, updated_by
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15
    ) RETURNING *`,
    [
      input.company_id,
      input.product_id || null,
      input.project_id || null,
      input.plan_id,
      input.status,
      input.start_date,
      input.end_date || null,
      input.renewal_date || null,
      input.grace_until || null,
      input.cancelled_at || null,
      input.suspended_at || null,
      input.notes || null,
      input.metadata || {},
      input.created_by || null,
      input.updated_by || null
    ]
  );
  return getById(res.rows[0].id, { client });
}

async function updateById(id, patch, { client = pool } = {}) {
  const current = await getById(id, { client, forUpdate: true });
  if (!current) return null;

  const res = await client.query(
    `UPDATE company_subscriptions
     SET company_id = $2,
         product_id = $3,
         project_id = $4,
         plan_id = $5,
         status = $6,
         start_date = $7,
         end_date = $8,
         renewal_date = $9,
         grace_until = $10,
         cancelled_at = $11,
         suspended_at = $12,
         notes = $13,
         metadata = $14,
         created_by = $15,
         updated_by = $16,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [
      id,
      patch.company_id === undefined ? current.company_id : patch.company_id,
      patch.product_id === undefined ? current.product_id : patch.product_id,
      patch.project_id === undefined ? current.project_id : patch.project_id,
      patch.plan_id === undefined ? current.plan_id : patch.plan_id,
      patch.status === undefined ? current.status : patch.status,
      patch.start_date === undefined ? current.start_date : patch.start_date,
      patch.end_date === undefined ? current.end_date : patch.end_date,
      patch.renewal_date === undefined ? current.renewal_date : patch.renewal_date,
      patch.grace_until === undefined ? current.grace_until : patch.grace_until,
      patch.cancelled_at === undefined ? current.cancelled_at : patch.cancelled_at,
      patch.suspended_at === undefined ? current.suspended_at : patch.suspended_at,
      patch.notes === undefined ? current.notes : patch.notes,
      patch.metadata === undefined ? current.metadata : patch.metadata,
      patch.created_by === undefined ? current.created_by : patch.created_by,
      patch.updated_by === undefined ? current.updated_by : patch.updated_by
    ]
  );
  return getById(res.rows[0].id, { client });
}

module.exports = {
  list,
  getById,
  create,
  updateById
};