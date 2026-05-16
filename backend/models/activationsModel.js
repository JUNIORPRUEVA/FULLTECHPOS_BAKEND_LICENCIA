const { pool } = require('../db/pool');

const STATUS_TO_LEGACY = {
  ACTIVE: 'ACTIVA',
  BLOCKED: 'REVOCADA',
  REVOKED: 'REVOCADA'
};

function legacyStatus(status) {
  return STATUS_TO_LEGACY[status] || 'REVOCADA';
}

async function safeUpdateLegacyEstado({ id, status, client }) {
  const q = client || pool;
  await q.query(
    `UPDATE license_activations
     SET estado = $2
     WHERE id = $1`,
    [id, legacyStatus(status)]
  );
}

function selectBase() {
  return `
    SELECT a.*,
           a.status,
           COALESCE(a.created_at, a.activated_at) AS created_at,
           COALESCE(a.last_seen_at, a.last_check_at) AS last_seen_at,
           l.license_key,
           l.estado AS license_status,
           l.license_type,
           l.expires_at,
           l.fecha_fin,
           l.max_dispositivos AS max_devices,
           c.id AS customer_id,
           c.nombre_negocio AS customer_name,
           c.contacto_email AS customer_email,
           cs.id AS subscription_id,
           cs.status AS subscription_status,
           cs.next_payment_date,
           pp.name AS plan_name,
           p.name AS product_name,
           pr.name AS project_name
    FROM license_activations a
    INNER JOIN licenses l ON l.id = a.license_id
    LEFT JOIN customers c ON c.id = l.customer_id
    LEFT JOIN company_subscriptions cs ON cs.id = l.subscription_id OR cs.license_id = l.id
    LEFT JOIN product_plans pp ON pp.id = cs.plan_id
    LEFT JOIN products p ON p.id = COALESCE(cs.product_id, l.product_id)
    LEFT JOIN projects pr ON pr.id = COALESCE(cs.project_id, l.project_id)
  `;
}

async function getActivationByLicenseAndDevice({ license_id, device_id, client }) {
  const q = client || pool;
  const res = await q.query(
    `SELECT * FROM license_activations
     WHERE license_id = $1 AND device_id = $2
     LIMIT 1`,
    [license_id, device_id]
  );
  return res.rows[0] || null;
}

async function getActivationByDevice({ device_id, client, activeOnly = true }) {
  const q = client || pool;
  const res = await q.query(
    `${selectBase()}
     WHERE a.device_id = $1
       ${activeOnly ? "AND a.status = 'ACTIVE'" : ''}
     ORDER BY COALESCE(a.last_seen_at, a.last_check_at) DESC
     LIMIT 2`,
    [device_id]
  );
  return res.rows;
}

async function getById(activationId, { client = pool } = {}) {
  const res = await client.query(`${selectBase()} WHERE a.id = $1 LIMIT 1`, [activationId]);
  return res.rows[0] || null;
}

async function countActiveActivations({ license_id, exclude_device_id = null, client }) {
  const q = client || pool;
  const params = [license_id];
  const where = [`license_id = $1`, `status = 'ACTIVE'`];
  if (exclude_device_id) {
    params.push(exclude_device_id);
    where.push(`device_id <> $${params.length}`);
  }

  const res = await q.query(
    `SELECT COUNT(*)::int AS total
     FROM license_activations
     WHERE ${where.join(' AND ')}`,
    params
  );
  return res.rows[0]?.total || 0;
}

async function createActivation({ license_id, device_id, device_name, device_type, ip_address, client }) {
  const q = client || pool;
  const res = await q.query(
    `INSERT INTO license_activations (
       license_id, device_id, device_name, device_type, ip_address,
       estado, status, activated_at, last_check_at, created_at, last_seen_at
     ) VALUES (
       $1, $2, $3, $4, $5, 'ACTIVA', 'ACTIVE', now(), now(), now(), now()
     )
     RETURNING *`,
    [license_id, device_id, device_name || null, device_type, ip_address || null]
  );
  return res.rows[0];
}

async function activateExisting({ activation_id, device_name, device_type, ip_address, client }) {
  const q = client || pool;
  const res = await q.query(
    `UPDATE license_activations
     SET status = 'ACTIVE',
         estado = 'ACTIVA',
         device_name = COALESCE($2, device_name),
         device_type = COALESCE($3, device_type),
         ip_address = COALESCE($4, ip_address),
         last_check_at = now(),
         last_seen_at = now()
     WHERE id = $1
     RETURNING *`,
    [activation_id, device_name || null, device_type || null, ip_address || null]
  );
  return res.rows[0] || null;
}

async function touchActivation({ activation_id, ip_address, client }) {
  const q = client || pool;
  const res = await q.query(
    `UPDATE license_activations
     SET last_check_at = now(),
         last_seen_at = now(),
         ip_address = COALESCE($2, ip_address)
     WHERE id = $1
     RETURNING *`,
    [activation_id, ip_address || null]
  );
  return res.rows[0] || null;
}

async function updateStatus(activationId, status, { client = pool, ip_address = null } = {}) {
  const res = await client.query(
    `UPDATE license_activations
     SET status = $2,
         ip_address = COALESCE($3, ip_address),
         last_seen_at = CASE WHEN $2 = 'ACTIVE' THEN now() ELSE last_seen_at END,
         last_check_at = CASE WHEN $2 = 'ACTIVE' THEN now() ELSE last_check_at END
     WHERE id = $1
     RETURNING *`,
    [activationId, status, ip_address]
  );
  const row = res.rows[0] || null;
  if (row) await safeUpdateLegacyEstado({ id: row.id, status, client });
  return row;
}

async function blockActivationsForLicense(licenseId, { client = pool } = {}) {
  const res = await client.query(
    `UPDATE license_activations
     SET status = 'BLOCKED'
     WHERE license_id = $1
       AND status = 'ACTIVE'
     RETURNING *`,
    [licenseId]
  );

  for (const row of res.rows) {
    await safeUpdateLegacyEstado({ id: row.id, status: 'BLOCKED', client });
  }
  return res.rows;
}

async function listActivations({ limit, offset, license_id, status, device_id }) {
  const where = [];
  const params = [];

  if (license_id) {
    params.push(license_id);
    where.push(`a.license_id = $${params.length}`);
  }
  if (status) {
    params.push(status);
    where.push(`a.status = $${params.length}`);
  }
  if (device_id) {
    params.push(device_id);
    where.push(`a.device_id = $${params.length}`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total
     FROM license_activations a
     ${whereSql}`,
    params
  );
  const total = totalRes.rows[0]?.total || 0;

  params.push(limit, offset);

  const rowsRes = await pool.query(
    `${selectBase()}
     ${whereSql}
     ORDER BY COALESCE(a.last_seen_at, a.last_check_at, a.activated_at) DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total, activations: rowsRes.rows };
}

async function revokeActivation(activationId, { client = pool } = {}) {
  return updateStatus(activationId, 'REVOKED', { client });
}

async function blockActivation(activationId, { client = pool } = {}) {
  return updateStatus(activationId, 'BLOCKED', { client });
}

module.exports = {
  getActivationByLicenseAndDevice,
  getActivationByDevice,
  getById,
  countActiveActivations,
  createActivation,
  activateExisting,
  touchActivation,
  updateStatus,
  blockActivationsForLicense,
  listActivations,
  revokeActivation,
  blockActivation
};
