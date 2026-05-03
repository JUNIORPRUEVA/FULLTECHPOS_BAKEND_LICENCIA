const { pool } = require('../db/pool');

function normalizeText(value, { lower = false } = {}) {
  if (value == null) return null;
  let next = String(value).trim();
  if (!next) return null;
  if (lower) next = next.toLowerCase();
  return next;
}

async function list({ status, user_type, q, limit = 50, offset = 0 } = {}) {
  const params = [];
  const where = [];

  if (status) {
    params.push(status);
    where.push(`pu.status = $${params.length}`);
  }
  if (user_type) {
    params.push(user_type);
    where.push(`pu.user_type = $${params.length}`);
  }
  if (q) {
    params.push(`%${String(q).trim().toLowerCase()}%`);
    where.push(`(lower(pu.email) LIKE $${params.length} OR lower(COALESCE(pu.display_name, '')) LIKE $${params.length})`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total FROM platform_users pu ${whereSql}`,
    params
  );

  params.push(limit, offset);
  const rowsRes = await pool.query(
    `SELECT pu.*
     FROM platform_users pu
     ${whereSql}
     ORDER BY pu.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total: totalRes.rows[0]?.total || 0, users: rowsRes.rows };
}

async function getById(id, { client = pool } = {}) {
  const res = await client.query('SELECT * FROM platform_users WHERE id = $1', [id]);
  return res.rows[0] || null;
}

async function getByEmail(email, { client = pool } = {}) {
  const normalized = normalizeText(email, { lower: true });
  if (!normalized) return null;
  const res = await client.query('SELECT * FROM platform_users WHERE lower(email) = $1', [normalized]);
  return res.rows[0] || null;
}

async function create(input, { client = pool } = {}) {
  const email = normalizeText(input.email, { lower: true });
  if (!email) throw new Error('email es requerido');

  const res = await client.query(
    `INSERT INTO platform_users (
      email, password_hash, display_name, phone, status, user_type, last_login_at
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7
    ) RETURNING *`,
    [
      email,
      input.password_hash || null,
      normalizeText(input.display_name),
      normalizeText(input.phone),
      normalizeText(input.status) || 'active',
      normalizeText(input.user_type) || 'admin',
      input.last_login_at || null
    ]
  );
  return res.rows[0] || null;
}

async function assignRole({ user_id, role_id, company_id }, { client = pool } = {}) {
  const existing = await client.query(
    `SELECT *
     FROM platform_user_roles
     WHERE user_id = $1 AND role_id = $2
       AND ((company_id IS NULL AND $3::uuid IS NULL) OR company_id = $3)
     LIMIT 1`,
    [user_id, role_id, company_id || null]
  );

  if (existing.rows[0]) return existing.rows[0];

  const res = await client.query(
    `INSERT INTO platform_user_roles (user_id, role_id, company_id)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [user_id, role_id, company_id || null]
  );
  return res.rows[0] || null;
}

module.exports = {
  list,
  getById,
  getByEmail,
  create,
  assignRole
};