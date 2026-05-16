const { pool } = require('../db/pool');

async function findLicenseByKey(licenseKey) {
  const res = await pool.query(
    `SELECT l.*, c.id AS customer_id_ref, c.nombre_negocio, c.business_id,
            p.id AS project_id_ref, p.code AS project_code, p.name AS project_name,
            pr.id AS product_id_ref, pr.slug AS product_slug, pr.name AS product_name
     FROM licenses l
     LEFT JOIN customers c ON c.id = l.customer_id
     LEFT JOIN projects p ON p.id = l.project_id
     LEFT JOIN products pr ON pr.id = l.product_id
     WHERE l.license_key = $1
     ORDER BY l.created_at DESC
     LIMIT 1`,
    [licenseKey]
  );
  return res.rows[0] || null;
}

async function findLatestLicenseByBusinessId(businessId, { product_id, project_id, device_id } = {}) {
  const params = [businessId];
  const where = ['c.business_id = $1'];
  let activationJoin = '';

  if (product_id) {
    params.push(product_id);
    where.push(`l.product_id = $${params.length}`);
  }
  if (project_id) {
    params.push(project_id);
    where.push(`l.project_id = $${params.length}`);
  }
  if (device_id) {
    params.push(device_id);
    activationJoin = `LEFT JOIN license_activations la
                      ON la.license_id = l.id
                     AND la.device_id = $${params.length}
                     AND COALESCE(la.status, CASE WHEN la.estado = 'ACTIVA' THEN 'ACTIVE' ELSE 'REVOKED' END) = 'ACTIVE'`;
  }

  const res = await pool.query(
    `SELECT l.*, c.id AS customer_id_ref, c.nombre_negocio, c.business_id,
            p.id AS project_id_ref, p.code AS project_code, p.name AS project_name,
            pr.id AS product_id_ref, pr.slug AS product_slug, pr.name AS product_name,
            ${device_id ? 'CASE WHEN la.id IS NULL THEN false ELSE true END AS device_match' : 'false AS device_match'}
     FROM licenses l
     INNER JOIN customers c ON c.id = l.customer_id
     LEFT JOIN projects p ON p.id = l.project_id
     LEFT JOIN products pr ON pr.id = l.product_id
     ${activationJoin}
     WHERE ${where.join(' AND ')}
     ORDER BY ${device_id ? 'device_match DESC,' : ''} COALESCE(l.issued_at, l.created_at) DESC, l.created_at DESC
     LIMIT 1`,
    params
  );
  return res.rows[0] || null;
}

async function findSubscriptionById(subscriptionId) {
  const res = await pool.query(
    `SELECT cs.*, pp.code AS plan_code, pp.name AS plan_name, pp.billing_period,
            pp.device_limit, pp.company_limit, pp.default_grace_days, pp.trial_days,
            pp.product_id AS plan_product_id, pp.project_id AS plan_project_id,
            p.slug AS product_slug, p.name AS product_name,
            pr.code AS project_code, pr.name AS project_name,
            c.name AS company_name
     FROM company_subscriptions cs
     INNER JOIN product_plans pp ON pp.id = cs.plan_id
     INNER JOIN companies c ON c.id = cs.company_id
     LEFT JOIN products p ON p.id = cs.product_id
     LEFT JOIN projects pr ON pr.id = cs.project_id
     WHERE cs.id = $1
     LIMIT 1`,
    [subscriptionId]
  );
  return res.rows[0] || null;
}

async function findLatestSubscriptionByFilters({ company_id, product_id, project_id }) {
  const params = [];
  const where = [];

  if (company_id) {
    params.push(company_id);
    where.push(`cs.company_id = $${params.length}`);
  }
  if (product_id) {
    params.push(product_id);
    where.push(`cs.product_id = $${params.length}`);
  }
  if (project_id) {
    params.push(project_id);
    where.push(`cs.project_id = $${params.length}`);
  }

  if (!where.length) return null;

  const res = await pool.query(
    `SELECT cs.*, pp.code AS plan_code, pp.name AS plan_name, pp.billing_period,
            pp.device_limit, pp.company_limit, pp.default_grace_days, pp.trial_days,
            pp.product_id AS plan_product_id, pp.project_id AS plan_project_id,
            p.slug AS product_slug, p.name AS product_name,
            pr.code AS project_code, pr.name AS project_name,
            c.name AS company_name
     FROM company_subscriptions cs
     INNER JOIN product_plans pp ON pp.id = cs.plan_id
     INNER JOIN companies c ON c.id = cs.company_id
     LEFT JOIN products p ON p.id = cs.product_id
     LEFT JOIN projects pr ON pr.id = cs.project_id
     WHERE ${where.join(' AND ')}
     ORDER BY cs.updated_at DESC, cs.created_at DESC
     LIMIT 1`,
    params
  );
  return res.rows[0] || null;
}

async function countActiveActivations(licenseId) {
  const res = await pool.query(
    `SELECT COUNT(*)::int AS total
     FROM license_activations
     WHERE license_id = $1
       AND COALESCE(status, CASE WHEN estado = 'ACTIVA' THEN 'ACTIVE' ELSE 'REVOKED' END) = 'ACTIVE'`,
    [licenseId]
  );
  return res.rows[0]?.total || 0;
}

async function findDeviceActivation(licenseId, deviceId) {
  if (!deviceId) return null;
  const res = await pool.query(
    `SELECT *
     FROM license_activations
     WHERE license_id = $1 AND device_id = $2
     LIMIT 1`,
    [licenseId, deviceId]
  );
  return res.rows[0] || null;
}

module.exports = {
  findLicenseByKey,
  findLatestLicenseByBusinessId,
  findSubscriptionById,
  findLatestSubscriptionByFilters,
  countActiveActivations,
  findDeviceActivation
};