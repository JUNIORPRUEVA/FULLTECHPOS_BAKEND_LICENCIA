const { pool } = require('../db/pool');

async function create(entry, { client = pool } = {}) {
  const res = await client.query(
    `INSERT INTO audit_logs (
      actor_user_id, actor_type, company_id, product_id, project_id, target_type,
      target_id, action, before_data, after_data, ip_address, user_agent
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12
    ) RETURNING *`,
    [
      entry.actor_user_id || null,
      entry.actor_type,
      entry.company_id || null,
      entry.product_id || null,
      entry.project_id || null,
      entry.target_type,
      String(entry.target_id),
      entry.action,
      entry.before_data || {},
      entry.after_data || {},
      entry.ip_address || null,
      entry.user_agent || null
    ]
  );
  return res.rows[0] || null;
}

async function list(filters = {}) {
  const {
    company_id,
    actor_user_id,
    target_type,
    action,
    date_from,
    date_to,
    limit = 100,
    offset = 0
  } = filters;
  const params = [];
  const where = [];

  for (const [field, value] of Object.entries({ company_id, actor_user_id, target_type, action })) {
    if (!value) continue;
    params.push(value);
    where.push(`al.${field} = $${params.length}`);
  }
  if (date_from) {
    params.push(date_from);
    where.push(`al.created_at >= $${params.length}`);
  }
  if (date_to) {
    params.push(date_to);
    where.push(`al.created_at <= $${params.length}`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total FROM audit_logs al ${whereSql}`,
    params
  );

  params.push(limit, offset);
  const rowsRes = await pool.query(
    `SELECT al.*, pu.email AS actor_email, c.name AS company_name
     FROM audit_logs al
     LEFT JOIN platform_users pu ON pu.id = al.actor_user_id
     LEFT JOIN companies c ON c.id = al.company_id
     ${whereSql}
     ORDER BY al.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total: totalRes.rows[0]?.total || 0, logs: rowsRes.rows };
}

module.exports = {
  create,
  list
};