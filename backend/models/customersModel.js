const { pool } = require('../db/pool');
const licensesModel = require('./licensesModel');
const { generateLicenseKey } = require('../utils/licenseKey');

function isPgMissingColumnOrTable(error) {
  const code = error && error.code;
  return code === '42703' || code === '42P01';
}

async function runOptional(client, sql, params = []) {
  try {
    return await client.query(sql, params);
  } catch (error) {
    if (isPgMissingColumnOrTable(error)) return null;
    throw error;
  }
}

async function getFullposProject(client = pool) {
  const result = await runOptional(
    client,
    `SELECT id, code, name, demo_days
     FROM projects
     WHERE code = 'FULLPOS'
     LIMIT 1`
  );
  return result?.rows?.[0] || null;
}

function computeTrialWindow(customer, project) {
  const trialStart = customer?.trial_start_at ? new Date(customer.trial_start_at) : null;
  if (!trialStart || Number.isNaN(trialStart.getTime())) return null;

  const demoDays = Number(project?.demo_days || 5);
  const trialEnd = new Date(trialStart.getTime() + demoDays * 24 * 60 * 60 * 1000);
  const now = new Date();
  const isActive = trialEnd.getTime() >= now.getTime();

  return {
    trialStart,
    trialEnd,
    demoDays,
    isActive,
    estado: isActive ? 'ACTIVA' : 'VENCIDA',
  };
}

async function createPersistedDemoLicense({ customer, project, trial, client = pool }) {
  let lastError = null;

  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      const created = await licensesModel.createLicenseWithKey({
        project_id: project.id,
        customer_id: customer.id,
        license_key: generateLicenseKey(),
        tipo: 'DEMO',
        license_type: 'SUSCRIPCION',
        dias_validez: trial.demoDays,
        max_dispositivos: 1,
        notas: `Demo ${trial.isActive ? 'activa' : 'historica'} sincronizada automaticamente desde trial_start_at`,
      });

      const note = created.notas || `Demo ${trial.isActive ? 'activa' : 'historica'} sincronizada automaticamente desde trial_start_at`;
      const updateAttempts = [
        `UPDATE licenses
         SET fecha_inicio = CAST($2 AS timestamp),
             fecha_fin = CAST($3 AS timestamp),
             expires_at = CAST($4 AS timestamptz),
             estado = $5,
             activation_source = 'trial_auto_persisted',
             notas = $6
         WHERE id = $1
         RETURNING *`,
        `UPDATE licenses
         SET fecha_inicio = CAST($2 AS timestamp),
             fecha_fin = CAST($3 AS timestamp),
             estado = $5,
             activation_source = 'trial_auto_persisted',
             notas = $6
         WHERE id = $1
         RETURNING *`,
        `UPDATE licenses
         SET fecha_inicio = CAST($2 AS timestamp),
             fecha_fin = CAST($3 AS timestamp),
             estado = $5,
             notas = $6
         WHERE id = $1
         RETURNING *`,
      ];

      for (const sql of updateAttempts) {
        try {
          const updated = await client.query(sql, [
            created.id,
            trial.trialStart,
            trial.trialEnd,
            trial.trialEnd,
            trial.estado,
            note,
          ]);
          return updated.rows[0] || created;
        } catch (error) {
          if (!isPgMissingColumnOrTable(error)) throw error;
        }
      }

      return created;
    } catch (error) {
      lastError = error;
      if (!(error && error.code === '23505')) throw error;
    }
  }

  throw lastError || new Error('No se pudo persistir la licencia demo');
}

async function ensurePersistedTrialLicense(customer, { client = pool } = {}) {
  if (!customer?.id || !customer?.trial_start_at) return { changed: false, license: null };

  const project = await getFullposProject(client);
  if (!project?.id) return { changed: false, license: null };

  const trial = computeTrialWindow(customer, project);
  if (!trial) return { changed: false, license: null };

  let existing = null;
  let hasDeletedMarker = false;

  const deletedMarkerQueries = [
    {
      sql: `SELECT id
            FROM licenses
            WHERE customer_id = $1
              AND project_id = $2
              AND tipo = 'DEMO'
              AND estado::text = 'ELIMINADA'
            ORDER BY created_at DESC
            LIMIT 1`,
      params: [customer.id, project.id],
    },
    {
      sql: `SELECT id
            FROM licenses
            WHERE customer_id = $1
              AND tipo = 'DEMO'
              AND estado::text = 'ELIMINADA'
            ORDER BY created_at DESC
            LIMIT 1`,
      params: [customer.id],
    }
  ];

  for (const attempt of deletedMarkerQueries) {
    try {
      const deletedRes = await client.query(attempt.sql, attempt.params);
      hasDeletedMarker = Boolean(deletedRes.rows[0]);
      break;
    } catch (error) {
      if (!isPgMissingColumnOrTable(error)) throw error;
    }
  }

  if (hasDeletedMarker) {
    return { changed: false, license: null };
  }

  const existingQueries = [
    {
      sql: `SELECT *
            FROM licenses
            WHERE customer_id = $1
              AND project_id = $2
              AND tipo = 'DEMO'
              AND estado::text <> 'ELIMINADA'
            ORDER BY created_at DESC
            LIMIT 1`,
      params: [customer.id, project.id],
    },
    {
      sql: `SELECT *
            FROM licenses
            WHERE customer_id = $1
              AND tipo = 'DEMO'
              AND estado::text <> 'ELIMINADA'
            ORDER BY created_at DESC
            LIMIT 1`,
      params: [customer.id],
    }
  ];

  for (const attempt of existingQueries) {
    try {
      const existingRes = await client.query(attempt.sql, attempt.params);
      existing = existingRes.rows[0] || null;
      break;
    } catch (error) {
      if (!isPgMissingColumnOrTable(error)) throw error;
    }
  }

  if (!existing) {
    const created = await createPersistedDemoLicense({ customer, project, trial, client });
    return { changed: true, license: created };
  }

  const currentStatus = String(existing.estado || '').trim().toUpperCase();
  const needsUpdate =
    !existing.fecha_inicio ||
    !existing.fecha_fin ||
    currentStatus !== trial.estado ||
    Number(existing.dias_validez || 0) !== trial.demoDays;

  if (!needsUpdate) {
    return { changed: false, license: existing };
  }

  const note = existing.notas || `Demo ${trial.isActive ? 'activa' : 'historica'} sincronizada automaticamente desde trial_start_at`;
  const updateAttempts = [
    `UPDATE licenses
     SET fecha_inicio = CAST($2 AS timestamp),
         fecha_fin = CAST($3 AS timestamp),
         expires_at = CAST($4 AS timestamptz),
         dias_validez = $5,
         estado = $6,
         activation_source = COALESCE(activation_source, 'trial_auto_persisted'),
         notas = $7
     WHERE id = $1
     RETURNING *`,
    `UPDATE licenses
     SET fecha_inicio = CAST($2 AS timestamp),
         fecha_fin = CAST($3 AS timestamp),
         dias_validez = $5,
         estado = $6,
         activation_source = COALESCE(activation_source, 'trial_auto_persisted'),
         notas = $7
     WHERE id = $1
     RETURNING *`,
    `UPDATE licenses
     SET fecha_inicio = CAST($2 AS timestamp),
         fecha_fin = CAST($3 AS timestamp),
         dias_validez = $5,
         estado = $6,
         notas = $7
     WHERE id = $1
     RETURNING *`,
  ];

  for (const sql of updateAttempts) {
    try {
      const updated = await client.query(sql, [
        existing.id,
        trial.trialStart,
        trial.trialEnd,
        trial.trialEnd,
        trial.demoDays,
        trial.estado,
        note,
      ]);
      return { changed: true, license: updated.rows[0] || existing };
    } catch (error) {
      if (!isPgMissingColumnOrTable(error)) throw error;
    }
  }

  return { changed: false, license: existing };
}

async function ensurePersistedTrialLicenses(customers, { client = pool } = {}) {
  let changed = false;
  for (const customer of customers || []) {
    const result = await ensurePersistedTrialLicense(customer, { client });
    if (result.changed) changed = true;
  }
  return changed;
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

  const commercialJoin = `
     LEFT JOIN LATERAL (
       SELECT
         EXISTS (
           SELECT 1
           FROM licenses lf
           WHERE lf.customer_id = c.id
             AND lf.tipo = 'FULL'
             AND lf.estado::text <> 'ELIMINADA'
         ) AS has_full_license,
         EXISTS (
           SELECT 1
           FROM licenses lf
           WHERE lf.customer_id = c.id
             AND lf.tipo = 'FULL'
             AND lf.estado::text = 'ACTIVA'
             AND (lf.fecha_fin IS NULL OR lf.fecha_fin >= NOW())
         ) AS has_active_full_license,
         EXISTS (
           SELECT 1
           FROM licenses lf
           WHERE lf.customer_id = c.id
             AND lf.tipo = 'FULL'
             AND lf.estado::text = 'BLOQUEADA'
         ) AS has_blocked_full_license,
         EXISTS (
           SELECT 1
           FROM licenses ld
           WHERE ld.customer_id = c.id
             AND ld.tipo = 'DEMO'
             AND ld.estado::text <> 'ELIMINADA'
         ) AS has_demo_license,
         EXISTS (
           SELECT 1
           FROM licenses ld
           WHERE ld.customer_id = c.id
             AND ld.tipo = 'DEMO'
             AND ld.estado::text = 'ACTIVA'
             AND (ld.fecha_fin IS NULL OR ld.fecha_fin >= NOW())
         ) AS has_active_demo_license,
         (
           SELECT MAX(lf.created_at)
           FROM licenses lf
           WHERE lf.customer_id = c.id
             AND lf.tipo = 'FULL'
             AND lf.estado::text <> 'ELIMINADA'
         ) AS last_full_purchase_at,
         (
           SELECT COUNT(*)::int
           FROM licenses lf
           WHERE lf.customer_id = c.id
             AND lf.tipo = 'FULL'
             AND lf.estado::text <> 'ELIMINADA'
         ) AS full_license_count,
         (
           SELECT COUNT(*)::int
           FROM licenses ld
           WHERE ld.customer_id = c.id
             AND ld.tipo = 'DEMO'
             AND ld.estado::text <> 'ELIMINADA'
         ) AS demo_license_count,
         CASE
           WHEN EXISTS (
             SELECT 1
             FROM licenses lf
             WHERE lf.customer_id = c.id
               AND lf.tipo = 'FULL'
               AND lf.estado::text = 'ACTIVA'
               AND (lf.fecha_fin IS NULL OR lf.fecha_fin >= NOW())
           ) THEN 'CLIENTE_ACTIVO'
           WHEN EXISTS (
             SELECT 1
             FROM licenses lf
             WHERE lf.customer_id = c.id
               AND lf.tipo = 'FULL'
               AND lf.estado::text = 'BLOQUEADA'
           ) THEN 'CLIENTE_BLOQUEADO'
           WHEN EXISTS (
             SELECT 1
             FROM licenses lf
             WHERE lf.customer_id = c.id
               AND lf.tipo = 'FULL'
               AND lf.estado::text <> 'ELIMINADA'
           ) THEN 'CLIENTE_VENCIDO'
           WHEN EXISTS (
             SELECT 1
             FROM licenses ld
             WHERE ld.customer_id = c.id
               AND ld.tipo = 'DEMO'
               AND ld.estado::text = 'ACTIVA'
               AND (ld.fecha_fin IS NULL OR ld.fecha_fin >= NOW())
           ) THEN 'DEMO_ACTIVA'
           WHEN EXISTS (
             SELECT 1
             FROM licenses ld
             WHERE ld.customer_id = c.id
               AND ld.tipo = 'DEMO'
               AND ld.estado::text <> 'ELIMINADA'
           ) THEN 'SOLO_DEMO'
           ELSE 'SIN_MOVIMIENTO'
         END AS commercial_status
     ) commercial_summary ON TRUE`;

  return `SELECT
      c.*,
      license_summary.license_id,
      license_summary.license_tipo,
      license_summary.license_status,
      license_summary.has_active_license,
      license_summary.has_license,
      commercial_summary.has_full_license,
      commercial_summary.has_active_full_license,
      commercial_summary.has_blocked_full_license,
      commercial_summary.has_demo_license,
      commercial_summary.has_active_demo_license,
      commercial_summary.last_full_purchase_at,
      commercial_summary.full_license_count,
      commercial_summary.demo_license_count,
      commercial_summary.commercial_status
     FROM customers c
     ${licenseJoin}
     ${commercialJoin}`;
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

  let customers = await queryCustomers({
    params: [limit, offset],
    orderLimitSql: `ORDER BY c.created_at DESC
                    LIMIT $1 OFFSET $2`
  });

  const changed = await ensurePersistedTrialLicenses(customers);
  if (changed) {
    customers = await queryCustomers({
      params: [limit, offset],
      orderLimitSql: `ORDER BY c.created_at DESC
                      LIMIT $1 OFFSET $2`
    });
  }

  return { total, customers };
}

async function getCustomerById(customerId) {
  let rows = await queryCustomers({
    whereSql: 'WHERE c.id = $1',
    params: [customerId],
    orderLimitSql: 'LIMIT 1'
  });
  if (rows[0]) {
    const changed = await ensurePersistedTrialLicenses(rows);
    if (changed) {
      rows = await queryCustomers({
        whereSql: 'WHERE c.id = $1',
        params: [customerId],
        orderLimitSql: 'LIMIT 1'
      });
    }
  }
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

async function setCustomerBusinessId({ customerId, business_id }, { client = pool } = {}) {
  try {
    const result = await client.query(
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

    const customerLicensesRes = await client.query(
      `SELECT id FROM licenses WHERE customer_id = $1`,
      [customerId]
    );
    const licenseIds = customerLicensesRes.rows.map((row) => row.id).filter(Boolean);

    await runOptional(
      client,
      `UPDATE company_subscriptions
       SET customer_id = NULL
       WHERE customer_id = $1`,
      [customerId]
    );

    if (licenseIds.length > 0) {
      await runOptional(
        client,
        `DELETE FROM company_licenses
         WHERE license_id = ANY($1::uuid[])`,
        [licenseIds]
      );

      await runOptional(
        client,
        `DELETE FROM sync_logs
         WHERE license_id = ANY($1::uuid[])`,
        [licenseIds]
      );

      await runOptional(
        client,
        `UPDATE company_subscriptions
         SET license_id = NULL
         WHERE license_id = ANY($1::uuid[])`,
        [licenseIds]
      );

      await runOptional(
        client,
        `UPDATE subscription_payments
         SET license_id = NULL
         WHERE license_id = ANY($1::uuid[])`,
        [licenseIds]
      );

      await runOptional(
        client,
        `UPDATE paypal_orders
         SET customer_id = CASE WHEN customer_id = $1 THEN NULL ELSE customer_id END,
             license_id = CASE WHEN license_id = ANY($2::uuid[]) THEN NULL ELSE license_id END
         WHERE customer_id = $1
            OR license_id = ANY($2::uuid[])`,
        [customerId, licenseIds]
      );

      await runOptional(
        client,
        `UPDATE licenses
         SET payment_order_id = NULL
         WHERE customer_id = $1`,
        [customerId]
      );

      try {
        await client.query(
          `DELETE FROM demo_trials
           WHERE customer_id = $1
              OR license_id = ANY($2::uuid[])`,
          [customerId, licenseIds]
        );
      } catch (error) {
        if (!(error && error.code === '42P01')) throw error;
      }
    } else {
      await runOptional(
        client,
        `UPDATE paypal_orders
         SET customer_id = NULL
         WHERE customer_id = $1`,
        [customerId]
      );

      try {
        await client.query(
          `DELETE FROM demo_trials WHERE customer_id = $1`,
          [customerId]
        );
      } catch (error) {
        if (!(error && error.code === '42P01')) throw error;
      }
    }

    let deletedPaymentOrdersCount = 0;
    try {
      const delPaymentsRes = await client.query(
        `DELETE FROM license_payment_orders
         WHERE customer_id = $1
         RETURNING id`,
        [customerId]
      );
      deletedPaymentOrdersCount = (delPaymentsRes.rows || []).length;
    } catch (error) {
      if (!(error && error.code === '42P01')) throw error;
    }

    const delLicensesRes = await client.query(
      `DELETE FROM licenses
       WHERE customer_id = $1
       RETURNING id`,
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
    return {
      deletedCustomer: delCustomerRes.rows[0],
      deletedLicensesCount,
      deletedPaymentOrdersCount,
    };
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    throw e;
  } finally {
    client.release();
  }
}

/**
 * Obtiene todas las licencias de un cliente con información del proyecto.
 */
async function getCustomerLicenses(customerId) {
  const customerRes = await pool.query(
    `SELECT *
     FROM customers
     WHERE id = $1
     LIMIT 1`,
    [customerId]
  );
  const customer = customerRes.rows[0] || null;
  if (customer) {
    await ensurePersistedTrialLicense(customer);
  }

  const tryQueries = [
    { includeProjects: true, includeBusinessId: true },
    { includeProjects: true, includeBusinessId: false },
    { includeProjects: false, includeBusinessId: true },
    { includeProjects: false, includeBusinessId: false }
  ];

  let lastError = null;
  for (const q of tryQueries) {
    try {
      const businessIdSelect = q.includeBusinessId ? 'c.business_id' : 'NULL::text AS business_id';
      const projectSelect = q.includeProjects
        ? 'p.code AS project_code, p.name AS project_name'
        : `'DEFAULT'::text AS project_code, NULL::text AS project_name`;
      const projectsJoin = q.includeProjects ? 'LEFT JOIN projects p ON p.id = l.project_id' : '';

      const result = await pool.query(
        `SELECT l.*, c.nombre_negocio, ${businessIdSelect}, ${projectSelect},
                CASE
                  WHEN l.fecha_fin IS NOT NULL THEN
                    GREATEST(0, EXTRACT(EPOCH FROM (l.fecha_fin - NOW())) / 86400)::int
                  ELSE NULL
                END AS days_remaining
         FROM licenses l
         LEFT JOIN customers c ON c.id = l.customer_id
         ${projectsJoin}
         WHERE l.customer_id = $1
           AND l.estado::text <> 'ELIMINADA'
         ORDER BY l.created_at DESC`,
        [customerId]
      );

      // Normalizar estado runtime
      const normalized = result.rows.map(row => {
        const estado = String(row.estado || '').trim().toUpperCase();
        let effectiveStatus = estado;
        if (estado === 'ACTIVA' && row.fecha_fin) {
          const expDate = new Date(row.fecha_fin);
          if (expDate < new Date()) {
            effectiveStatus = 'VENCIDA';
          }
        }
        return { ...row, estado: effectiveStatus };
      });

      return normalized;
    } catch (e) {
      lastError = e;
      if (!isPgMissingColumnOrTable(e)) throw e;
    }
  }
  throw lastError || new Error('No se pudieron obtener las licencias del cliente');
}

/**
 * Obtiene los pagos de un cliente.
 */
async function getCustomerPayments(customerId) {
  try {
    const result = await pool.query(
      `SELECT * FROM license_payment_orders
       WHERE customer_id = $1
       ORDER BY created_at DESC`,
      [customerId]
    );
    return result.rows;
  } catch (e) {
    // Si la tabla no existe, devolver array vacío
    if (e && e.code === '42P01') {
      return [];
    }
    throw e;
  }
}

/**
 * Cuenta licencias activas (no vencidas, no eliminadas) de un cliente.
 */
async function countCustomerActiveLicenses(customerId) {
  const result = await pool.query(
    `SELECT COUNT(*)::int AS count FROM licenses
     WHERE customer_id = $1
       AND estado::text <> 'ELIMINADA'
       AND (estado::text <> 'VENCIDA')
       AND (estado::text <> 'ACTIVA' OR (estado::text = 'ACTIVA' AND (fecha_fin IS NULL OR fecha_fin >= NOW())))`,
    [customerId]
  );
  return result.rows[0]?.count || 0;
}

/**
 * Cuenta pagos de un cliente.
 */
async function countCustomerPayments(customerId) {
  try {
    const result = await pool.query(
      `SELECT COUNT(*)::int AS count FROM license_payment_orders WHERE customer_id = $1`,
      [customerId]
    );
    return result.rows[0]?.count || 0;
  } catch (e) {
    if (e && e.code === '42P01') return 0;
    throw e;
  }
}

async function updateCustomer(customerId, fields) {
  const allowed = ['nombre_negocio', 'contacto_nombre', 'contacto_telefono', 'contacto_email', 'rol_negocio', 'business_id'];
  const sets = [];
  const params = [];
  let idx = 1;

  for (const k of allowed) {
    if (Object.prototype.hasOwnProperty.call(fields, k)) {
      sets.push(`${k} = $${idx}`);
      params.push(fields[k] === null ? null : fields[k]);
      idx += 1;
    }
  }

  if (!sets.length) return null;

  params.push(customerId);
  const sql = `UPDATE customers SET ${sets.join(', ')} WHERE id = $${idx} RETURNING *`;
  const result = await pool.query(sql, params);
  return result.rows[0] || null;
}

module.exports = {
  createCustomer,
  listCustomers,
  getCustomerById,
  getCustomerByBusinessId,
  setCustomerBusinessId,
  findCustomerByContact,
  deleteCustomerCascade,
  getCustomerLicenses,
  getCustomerPayments,
  countCustomerActiveLicenses,
  countCustomerPayments,
  updateCustomer,
  ensurePersistedTrialLicense,
  ensurePersistedTrialLicenses
};
