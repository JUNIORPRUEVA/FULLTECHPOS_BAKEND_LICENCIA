const { pool } = require('../db/pool');

async function getActivationByLicenseAndDevice({ license_id, device_id, client }) {
  const q = client || pool;
  const res = await q.query(
    `SELECT * FROM license_activations
     WHERE license_id = $1 AND device_id = $2`,
    [license_id, device_id]
  );
  return res.rows[0] || null;
}

async function countActiveActivations({ license_id, client }) {
  const q = client || pool;
  const res = await q.query(
    `SELECT COUNT(*)::int AS total
     FROM license_activations
     WHERE license_id = $1 AND estado = 'ACTIVA'`,
    [license_id]
  );
  return res.rows[0]?.total || 0;
}

async function createActivation({ license_id, device_id, client }) {
  const q = client || pool;
  const res = await q.query(
    `INSERT INTO license_activations (license_id, device_id, estado)
     VALUES ($1, $2, 'ACTIVA')
     RETURNING *`,
    [license_id, device_id]
  );
  return res.rows[0];
}

async function touchActivation({ activation_id, client }) {
  const q = client || pool;
  await q.query(
    `UPDATE license_activations
     SET last_check_at = now()
     WHERE id = $1`,
    [activation_id]
  );
}

async function listActivations({ limit, offset, license_id, estado }) {
  const where = [];
  const params = [];

  if (license_id) {
    params.push(license_id);
    where.push(`a.license_id = $${params.length}`);
  }
  if (estado) {
    params.push(estado);
    where.push(`a.estado = $${params.length}`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total
     FROM license_activations a
     ${whereSql}`,
    params
  );
  const total = totalRes.rows[0]?.total || 0;

  params.push(limit);
  params.push(offset);

  const rowsRes = await pool.query(
    `SELECT a.*, l.license_key, l.customer_id, c.nombre_negocio
     FROM license_activations a
     JOIN licenses l ON l.id = a.license_id
     LEFT JOIN customers c ON c.id = l.customer_id
     ${whereSql}
     ORDER BY a.activated_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total, activations: rowsRes.rows };
}

async function revokeActivation(activationId) {
  const res = await pool.query(
    `UPDATE license_activations
     SET estado = 'REVOCADA'
     WHERE id = $1
     RETURNING *`,
    [activationId]
  );
  return res.rows[0] || null;
}

module.exports = {
  getActivationByLicenseAndDevice,
  countActiveActivations,
  createActivation,
  touchActivation,
  listActivations,
  revokeActivation
};
