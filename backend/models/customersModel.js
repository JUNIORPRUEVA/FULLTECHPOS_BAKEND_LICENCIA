const { pool } = require('../db/pool');

function isPgMissingColumnOrTable(error) {
  const code = error && error.code;
  return code === '42703' || code === '42P01';
}

function buildCustomersSelectSql(includeLicenseSummary) {
  const licenseJoin = includeLicenseSummary
    ? `
     LEFT JOIN LATERAL (
       SELECT
         l.id AS license_id,
         l.tipo AS license_tipo,
         CASE
           WHEN l.estado = 'ACTIVA' AND l.fecha_fin IS NOT NULL AND l.fecha_fin < NOW() THEN 'VENCIDA'
           ELSE l.estado::text
         END AS license_status,
         (l.estado = 'ACTIVA' AND (l.fecha_fin IS NULL OR l.fecha_fin >= NOW())) AS has_active_license,
         TRUE AS has_license
       FROM licenses l
       WHERE l.customer_id = c.id
         AND l.estado::text <> 'ELIMINADA'
       ORDER BY
         CASE
           WHEN l.estado = 'ACTIVA' AND (l.fecha_fin IS NULL OR l.fecha_fin >= NOW()) THEN 0
           ELSE 1
         END,
         l.created_at DESC
       LIMIT 1
     ) license_summary ON TRUE`
    : `
     LEFT JOIN LATERAL (
       SELECT
         NULL::uuid AS license_id,
         NULL::text AS license_tipo,
         NULL::text AS license_status,
         FALSE AS has_active_license,
         FALSE AS has_license
     ) license_summary ON TRUE`;

  return `SELECT
      c.*,
      license_summary.license_id,
      license_summary.license_tipo,
      license_summary.license_status,
      license_summary.has_active_license,
      license_summary.has_license
     FROM customers c
     ${licenseJoin}`;
}

async function queryCustomers({ whereSql = '', params = [], orderLimitSql = '' } = {}) {
  const attempts = [true, false];
  let lastError = null;

  for (const includeLicenseSummary of attempts) {
    try {
      const result = await pool.query(
        `${buildCustomersSelectSql(includeLicenseSummary)}
         ${whereSql}
         ${orderLimitSql}`,
        params
      );
      return result.rows;
    } catch (error) {
      lastError = error;
      if (!isPgMissingColumnOrTable(error)) throw error;
    }
  }

  throw lastError;
}

async function createCustomer({ nombre_negocio, contacto_nombre, contacto_telefono, contacto_email, rol_negocio, business_id }) {
  try {
    if (business_id) {
      const result = await pool.query(
        `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email, rol_negocio, business_id)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [
          nombre_negocio,
          contacto_nombre || null,
          contacto_telefono || null,
          contacto_email || null,
          rol_negocio || null,
          String(business_id).trim()
        ]
      );
      return result.rows[0];
    }

    const result = await pool.query(
      `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email, rol_negocio)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [nombre_negocio, contacto_nombre || null, contacto_telefono || null, contacto_email || null, rol_negocio || null]
    );
    return result.rows[0];
  } catch (e) {
    // 42703 = undefined_column (migration pending)
    if (e && e.code === '42703') {
      const result = await pool.query(
        `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email)
         VALUES ($1, $2, $3, $4)
         RETURNING *`,
        [nombre_negocio, contacto_nombre || null, contacto_telefono || null, contacto_email || null]
      );
      return result.rows[0];
    }
    throw e;
  }
}

async function listCustomers({ limit, offset }) {
  const totalRes = await pool.query('SELECT COUNT(*)::int AS total FROM customers');
  const total = totalRes.rows[0]?.total || 0;

  const customers = await queryCustomers({
    params: [limit, offset],
    orderLimitSql: `ORDER BY c.created_at DESC
                    LIMIT $1 OFFSET $2`
  });

  return { total, customers };
}

async function getCustomerById(customerId) {
  const rows = await queryCustomers({
    whereSql: 'WHERE c.id = $1',
    params: [customerId],
    orderLimitSql: 'LIMIT 1'
  });
  return rows[0] || null;
}

async function getCustomerByBusinessId(businessId) {
  const id = String(businessId || '').trim();
  if (!id) return null;

  try {
    const result = await pool.query('SELECT * FROM customers WHERE business_id = $1 LIMIT 1', [id]);
    return result.rows[0] || null;
  } catch (e) {
    // 42703 = undefined_column (migration pending)
    if (e && e.code === '42703') {
      const err = new Error('customers.business_id column missing');
      err.code = 'MIGRATION_PENDING';
      throw err;
    }
    throw e;
  }
}

async function setCustomerBusinessId({ customerId, business_id }) {
  try {
    const result = await pool.query(
      'UPDATE customers SET business_id = $2 WHERE id = $1 RETURNING *',
      [customerId, business_id]
    );
    return result.rows[0] || null;
  } catch (e) {
    // 42703 = undefined_column (migration pending)
    if (e && e.code === '42703') {
      const err = new Error('customers.business_id column missing');
      err.code = 'MIGRATION_PENDING';
      throw err;
    }
    throw e;
  }
}

function normalizeEmail(email) {
  const value = String(email || '').trim();
  return value ? value.toLowerCase() : '';
}

function normalizePhone(phone) {
  return String(phone || '').replace(/[^0-9]/g, '');
}

async function findCustomerByContact({ contacto_email, contacto_telefono }) {
  const email = normalizeEmail(contacto_email);
  const phone = normalizePhone(contacto_telefono);

  if (!email && !phone) return null;

  const clauses = [];
  const params = [];

  if (email) {
    params.push(email);
    clauses.push(`lower(contacto_email) = $${params.length}`);
  }

  if (phone) {
    params.push(phone);
    clauses.push(`regexp_replace(coalesce(contacto_telefono, ''), '[^0-9]', '', 'g') = $${params.length}`);
  }

  const sql = `SELECT * FROM customers WHERE ${clauses.join(' OR ')} ORDER BY created_at ASC LIMIT 1`;
  const res = await pool.query(sql, params);
  return res.rows[0] || null;
}

async function deleteCustomerCascade(customerId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Delete licenses first (licenses.customer_id is RESTRICT). Activations cascade from licenses.
    const delLicensesRes = await client.query(
      'DELETE FROM licenses WHERE customer_id = $1 RETURNING id',
      [customerId]
    );
    const deletedLicensesCount = (delLicensesRes.rows || []).length;

    const delCustomerRes = await client.query(
      'DELETE FROM customers WHERE id = $1 RETURNING *',
      [customerId]
    );

    if (!delCustomerRes.rows || !delCustomerRes.rows[0]) {
      await client.query('ROLLBACK');
      return null;
    }

    await client.query('COMMIT');
    return { deletedCustomer: delCustomerRes.rows[0], deletedLicensesCount };
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    throw e;
  } finally {
    client.release();
  }
}

module.exports = {
  createCustomer,
  listCustomers,
  getCustomerById,
  getCustomerByBusinessId,
  setCustomerBusinessId,
  findCustomerByContact,
  deleteCustomerCascade
};
