const { pool } = require('../db/pool');
const activationsModel = require('./activationsModel');

const ACTIVATION_BLOCKING_LICENSE_STATES = new Set(['BLOQUEADA', 'VENCIDA', 'ELIMINADA']);

function isPgMissingColumnOrTable(e) {
  const code = e && e.code;
  // 42703 undefined_column, 42P01 undefined_table
  return code === '42703' || code === '42P01';
}

function isLicenseExpiredByDate(license, now = new Date()) {
  if (!license || !license.fecha_fin) return false;
  const endsAt = new Date(license.fecha_fin);
  if (Number.isNaN(endsAt.getTime())) return false;
  return endsAt.getTime() < now.getTime();
}

function getEffectiveLicenseStatus(license, now = new Date()) {
  const current = String(license?.estado || '').trim().toUpperCase();
  if (current === 'ACTIVA' && isLicenseExpiredByDate(license, now)) {
    return 'VENCIDA';
  }
  return current;
}

async function normalizeLicenseRuntimeStatus(license) {
  if (!license) return license;

  const nextStatus = getEffectiveLicenseStatus(license);
  if (nextStatus === 'VENCIDA' && String(license.estado || '').trim().toUpperCase() !== 'VENCIDA') {
    try {
      await markLicenseExpired(license.id);
    } catch (_) {}
  }

  return {
    ...license,
    estado: nextStatus || license.estado,
  };
}

async function createLicenseWithKey({
  project_id,
  customer_id,
  license_key,
  tipo,
  license_type,
  dias_validez,
  max_dispositivos,
  notas
}) {
  const normalizedLicenseType = String(license_type || 'SUSCRIPCION').trim().toUpperCase() === 'PERMANENTE'
    ? 'PERMANENTE'
    : 'SUSCRIPCION';

  // Intentar con schema completo primero, luego degradar si faltan columnas
  const attempts = [
    // Attempt 1: schema completo con project_id y license_type
    async () => {
      const result = await pool.query(
        `INSERT INTO licenses (project_id, customer_id, license_key, tipo, license_type, dias_validez, max_dispositivos, estado, notas)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'PENDIENTE', $8)
         RETURNING *`,
        [project_id, customer_id || null, license_key, tipo, normalizedLicenseType, dias_validez, max_dispositivos, notas || null]
      );
      return result.rows[0];
    },
    // Attempt 2: sin license_type
    async () => {
      const result = await pool.query(
        `INSERT INTO licenses (project_id, customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, notas)
         VALUES ($1, $2, $3, $4, $5, $6, 'PENDIENTE', $7)
         RETURNING *`,
        [project_id, customer_id || null, license_key, tipo, dias_validez, max_dispositivos, notas || null]
      );
      return result.rows[0];
    },
    // Attempt 3: sin project_id ni license_type (schema legacy)
    async () => {
      const result = await pool.query(
        `INSERT INTO licenses (customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, notas)
         VALUES ($1, $2, $3, $4, $5, 'PENDIENTE', $6)
         RETURNING *`,
        [customer_id || null, license_key, tipo, dias_validez, max_dispositivos, notas || null]
      );
      return result.rows[0];
    }
  ];

  for (const attempt of attempts) {
    try {
      return await attempt();
    } catch (e) {
      // Si es error de columna faltante, intentar siguiente schema
      if (isPgMissingColumnOrTable(e)) {
        continue;
      }
      // Si es unique violation (license_key duplicado), propagar para que el caller reintente
      if (e && e.code === '23505') {
        throw e;
      }
      // Para cualquier otro error, propagar
      throw e;
    }
  }

  // Si todos los intentos fallaron por schema, lanzar el último error
  throw new Error('No se pudo insertar la licencia: schema de base de datos incompatible');
}

async function listLicenses({ limit, offset, project_id, customer_id, tipo, estado, excludeEstados }) {
  const baseFilters = [];
  if (project_id) baseFilters.push({ key: 'project_id', field: 'l.project_id', value: project_id });
  if (customer_id) baseFilters.push({ key: 'customer_id', field: 'l.customer_id', value: customer_id });
  if (tipo) baseFilters.push({ key: 'tipo', field: 'l.tipo', value: tipo });
  if (estado) baseFilters.push({ key: 'estado', field: 'l.estado', value: estado });

  const buildWhere = ({ includeProjectFilter }) => {
    const where = [];
    const params = [];

    for (const f of baseFilters) {
      if (f.key === 'project_id' && !includeProjectFilter) continue;

      if (f.key === 'estado') {
        const normalizedState = String(f.value || '').trim().toUpperCase();
        if (normalizedState === 'VENCIDA') {
          params.push(normalizedState);
          where.push(`(l.estado = $${params.length} OR (l.estado = 'ACTIVA' AND l.fecha_fin IS NOT NULL AND l.fecha_fin < NOW()))`);
          continue;
        }

        if (normalizedState === 'ACTIVA') {
          params.push(normalizedState);
          where.push(`(l.estado = $${params.length} AND (l.fecha_fin IS NULL OR l.fecha_fin >= NOW()))`);
          continue;
        }
      }

      params.push(f.value);
      where.push(`${f.field} = $${params.length}`);
    }

    const excluded = Array.isArray(excludeEstados)
      ? excludeEstados.map((x) => String(x || '').trim().toUpperCase()).filter(Boolean)
      : [];
    if (excluded.length) {
      params.push(excluded);
      // `l.estado` is usually an ENUM (license_estado). Comparing ENUM = text errors.
      // Cast to text for safe filtering even when exclude list contains values
      // not present in the enum (e.g., soft-delete 'ELIMINADA' on older schemas).
      where.push(`NOT (l.estado::text = ANY($${params.length}::text[]))`);
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    return { whereSql, params };
  };

  // Some deployments may not have licenses.project_id yet.
  // In that case, we drop the project filter instead of throwing 500.
  let includeProjectFilter = true;
  for (let projectFilterAttempt = 0; projectFilterAttempt < 2; projectFilterAttempt++) {
    const { whereSql, params: filterParams } = buildWhere({ includeProjectFilter });

    let total = 0;
    try {
      const totalRes = await pool.query(
        `SELECT COUNT(*)::int AS total
         FROM licenses l
         ${whereSql}`,
        filterParams
      );
      total = totalRes.rows[0]?.total || 0;
    } catch (e) {
      if (
        includeProjectFilter &&
        isPgMissingColumnOrTable(e) &&
        String(e.message || '').toLowerCase().includes('project_id')
      ) {
        includeProjectFilter = false;
        continue;
      }
      throw e;
    }

    const params = [...filterParams, limit, offset];
    const limitParamIndex = params.length - 1;
    const offsetParamIndex = params.length;

  const tryQueries = [
    // Newest schema
    {
      includeProjects: true,
      includeBusinessId: true
    },
    // Missing customers.business_id
    {
      includeProjects: true,
      includeBusinessId: false
    },
    // Missing projects table/columns
    {
      includeProjects: false,
      includeBusinessId: true
    },
    // Missing both
    {
      includeProjects: false,
      includeBusinessId: false
    }
  ];

    let lastError = null;
    for (const q of tryQueries) {
      try {
      const businessIdSelect = q.includeBusinessId ? 'c.business_id' : 'NULL::text AS business_id';
      const projectSelect = q.includeProjects
        ? 'p.code AS project_code, p.name AS project_name'
        : `'DEFAULT'::text AS project_code, NULL::text AS project_name`;
      const projectsJoin = q.includeProjects ? 'LEFT JOIN projects p ON p.id = l.project_id' : '';

      const rowsRes = await pool.query(
        `SELECT l.*, c.nombre_negocio, ${businessIdSelect}, ${projectSelect}
         FROM licenses l
         LEFT JOIN customers c ON c.id = l.customer_id
         ${projectsJoin}
         ${whereSql}
         ORDER BY l.created_at DESC
         LIMIT $${limitParamIndex} OFFSET $${offsetParamIndex}`,
        params
      );
      const normalizedRows = await Promise.all(
        rowsRes.rows.map((row) => normalizeLicenseRuntimeStatus(row))
      );
      return { total, licenses: normalizedRows };
      } catch (e) {
        lastError = e;
        if (
          includeProjectFilter &&
          isPgMissingColumnOrTable(e) &&
          String(e.message || '').toLowerCase().includes('project_id')
        ) {
          // Drop project filter and retry the whole function.
          includeProjectFilter = false;
          break;
        }
        if (!isPgMissingColumnOrTable(e)) throw e;
      }
    }

    if (!includeProjectFilter) {
      // retry outer loop
      continue;
    }

    throw lastError;
  }

  // Should be unreachable.
  return { total: 0, licenses: [] };
}

async function getLicenseById(licenseId) {
  let license = null;
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

      const licRes = await pool.query(
        `SELECT l.*, c.nombre_negocio, ${businessIdSelect}, ${projectSelect}
         FROM licenses l
         LEFT JOIN customers c ON c.id = l.customer_id
         ${projectsJoin}
         WHERE l.id = $1`,
        [licenseId]
      );
      license = licRes.rows[0] || null;
      break;
    } catch (e) {
      lastError = e;
      if (!isPgMissingColumnOrTable(e)) throw e;
    }
  }

  if (lastError && !license) throw lastError;
  if (!license) return null;

  license = await normalizeLicenseRuntimeStatus(license);

  const actRes = await pool.query(
    `SELECT *
     FROM license_activations
     WHERE license_id = $1
     ORDER BY activated_at DESC`,
    [licenseId]
  );

  return { ...license, activations: actRes.rows };
}

async function updateLicenseStatus(licenseId, estado) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const res = await client.query(
      `UPDATE licenses
       SET estado = $2
       WHERE id = $1
       RETURNING *`,
      [licenseId, estado]
    );
    const updated = res.rows[0] || null;
    if (updated && ACTIVATION_BLOCKING_LICENSE_STATES.has(String(estado).toUpperCase())) {
      await activationsModel.blockActivationsForLicense(licenseId, { client });
    }
    await client.query('COMMIT');
    return updated;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function deleteLicense(licenseId) {
  // Soft-delete: mantener registro para auditoría y para que el endpoint
  // /businesses/:business_id/license pueda distinguir una revocación explícita
  // (no debe volver a emitir TRIAL si el admin eliminó la licencia).
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const res = await client.query(
      `UPDATE licenses
       SET estado = 'ELIMINADA'
       WHERE id = $1
       RETURNING *`,
      [licenseId]
    );
    const updated = res.rows[0] || null;
    if (updated) await activationsModel.blockActivationsForLicense(licenseId, { client });
    await client.query('COMMIT');
    return updated;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function updateLicense(licenseId, patch) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const licRes = await client.query('SELECT * FROM licenses WHERE id = $1 FOR UPDATE', [licenseId]);
    const current = licRes.rows[0];
    if (!current) {
      await client.query('ROLLBACK');
      return null;
    }

    const nextCustomerId = patch.customer_id != null ? patch.customer_id : current.customer_id;
    const nextProjectId = patch.project_id != null ? patch.project_id : current.project_id;
    const nextTipo = patch.tipo != null ? patch.tipo : current.tipo;
    const nextDias = patch.dias_validez != null ? patch.dias_validez : (current.dias_validez || 30);
    const nextMax = patch.max_dispositivos != null ? patch.max_dispositivos : (current.max_dispositivos || 1);
    const nextNotas = patch.notas !== undefined ? patch.notas : current.notas;
    const nextEstado = patch.estado != null ? patch.estado : current.estado;
    const nextLicenseType = patch.license_type != null
      ? (String(patch.license_type).trim().toUpperCase() === 'PERMANENTE' ? 'PERMANENTE' : 'SUSCRIPCION')
      : (current.license_type || 'SUSCRIPCION');

    let nextFechaInicio = current.fecha_inicio;
    let nextFechaFin = current.fecha_fin;

    // Reglas de fechas por cambio de estado
    if (nextLicenseType === 'PERMANENTE') {
      if (patch.estado === 'ACTIVA' && !nextFechaInicio) nextFechaInicio = new Date();
      nextFechaFin = null;
    } else if (patch.estado === 'PENDIENTE') {
      nextFechaInicio = null;
      nextFechaFin = null;
    } else if (patch.estado === 'ACTIVA') {
      const now = new Date();
      if (!nextFechaInicio) nextFechaInicio = now;
      nextFechaFin = new Date(new Date(nextFechaInicio).getTime() + Number(nextDias) * 24 * 60 * 60 * 1000);
    } else if (patch.dias_validez != null) {
      // Si ya estaba activa/iniciada y cambian días, recalcular fecha_fin
      if (nextFechaInicio) {
        nextFechaFin = new Date(new Date(nextFechaInicio).getTime() + Number(nextDias) * 24 * 60 * 60 * 1000);
      }
    }

    // Intentar UPDATE con schema completo, degradar si faltan columnas
    const updateAttempts = [
      // Attempt 1: schema completo con license_type
      async () => {
        return await client.query(
          `UPDATE licenses
           SET customer_id = $2,
               project_id = $3,
               tipo = $4,
               dias_validez = $5,
               max_dispositivos = $6,
               estado = $7,
               notas = $8,
               fecha_inicio = $9,
               fecha_fin = $10,
               expires_at = $10,
               license_type = $11
           WHERE id = $1
           RETURNING *`,
          [
            licenseId,
            nextCustomerId,
            nextProjectId,
            nextTipo,
            Number(nextDias),
            Number(nextMax),
            nextEstado,
            nextNotas,
            nextFechaInicio,
            nextFechaFin,
            nextLicenseType
          ]
        );
      },
      // Attempt 2: sin license_type
      async () => {
        return await client.query(
          `UPDATE licenses
           SET customer_id = $2,
               project_id = $3,
               tipo = $4,
               dias_validez = $5,
               max_dispositivos = $6,
               estado = $7,
               notas = $8,
               fecha_inicio = $9,
               fecha_fin = $10,
               expires_at = $10
           WHERE id = $1
           RETURNING *`,
          [
            licenseId,
            nextCustomerId,
            nextProjectId,
            nextTipo,
            Number(nextDias),
            Number(nextMax),
            nextEstado,
            nextNotas,
            nextFechaInicio,
            nextFechaFin
          ]
        );
      },
      // Attempt 3: sin project_id ni license_type
      async () => {
        return await client.query(
          `UPDATE licenses
           SET customer_id = $2,
               tipo = $3,
               dias_validez = $4,
               max_dispositivos = $5,
               estado = $6,
               notas = $7,
               fecha_inicio = $8,
               fecha_fin = $9,
               expires_at = $9
           WHERE id = $1
           RETURNING *`,
          [
            licenseId,
            nextCustomerId,
            nextTipo,
            Number(nextDias),
            Number(nextMax),
            nextEstado,
            nextNotas,
            nextFechaInicio,
            nextFechaFin
          ]
        );
      }
    ];

    let updRes = null;
    let lastUpdateError = null;
    for (const attempt of updateAttempts) {
      try {
        updRes = await attempt();
        break;
      } catch (e) {
        lastUpdateError = e;
        if (isPgMissingColumnOrTable(e)) {
          continue;
        }
        throw e;
      }
    }

    if (!updRes) {
      throw lastUpdateError || new Error('No se pudo actualizar la licencia');
    }

    if (ACTIVATION_BLOCKING_LICENSE_STATES.has(String(nextEstado).toUpperCase())) {
      await activationsModel.blockActivationsForLicense(licenseId, { client });
    }

    await client.query('COMMIT');
    return updRes.rows[0] || null;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function activateLicenseManually(licenseId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const licRes = await client.query('SELECT * FROM licenses WHERE id = $1 FOR UPDATE', [licenseId]);
    const license = licRes.rows[0];
    if (!license) {
      await client.query('ROLLBACK');
      return null;
    }

    const now = new Date();
    const msPerDay = 24 * 60 * 60 * 1000;
    const daysRaw = Number(license.dias_validez);
    const days = Number.isFinite(daysRaw) && daysRaw > 0 ? daysRaw : 1;

    let fecha_inicio = license.fecha_inicio;
    let fecha_fin = license.fecha_fin;
    // Intentar leer license_type, si no existe la columna, asumir SUSCRIPCION
    let licenseType = 'SUSCRIPCION';
    try {
      licenseType = String(license.license_type || 'SUSCRIPCION').trim().toUpperCase();
    } catch (_) {
      licenseType = 'SUSCRIPCION';
    }

    const fechaFinMs = fecha_fin ? new Date(fecha_fin).getTime() : NaN;
    const isFechaFinValid = Number.isFinite(fechaFinMs);
    const isExpiredByDate = isFechaFinValid ? fechaFinMs < now.getTime() : false;

    // Activación/Desbloqueo manual debe dejar la licencia utilizable.
    // Si no tiene fechas o ya venció por fecha, rearmar un nuevo período desde ahora.
    if (licenseType === 'PERMANENTE') {
      if (!fecha_inicio) fecha_inicio = now;
      fecha_fin = null;
    } else if (!fecha_inicio || !fecha_fin || isExpiredByDate) {
      fecha_inicio = now;
      fecha_fin = new Date(now.getTime() + days * msPerDay);
    }

    // Intentar UPDATE con expires_at, degradar si no existe la columna
    const activateAttempts = [
      async () => {
        return await client.query(
          `UPDATE licenses
          SET estado = 'ACTIVA', fecha_inicio = $2, fecha_fin = $3, expires_at = $3
           WHERE id = $1
           RETURNING *`,
          [licenseId, fecha_inicio, fecha_fin]
        );
      },
      async () => {
        return await client.query(
          `UPDATE licenses
          SET estado = 'ACTIVA', fecha_inicio = $2, fecha_fin = $3
           WHERE id = $1
           RETURNING *`,
          [licenseId, fecha_inicio, fecha_fin]
        );
      }
    ];

    let activateRes = null;
    let lastActivateError = null;
    for (const attempt of activateAttempts) {
      try {
        activateRes = await attempt();
        break;
      } catch (e) {
        lastActivateError = e;
        if (isPgMissingColumnOrTable(e)) {
          continue;
        }
        throw e;
      }
    }

    if (!activateRes) {
      throw lastActivateError || new Error('No se pudo activar la licencia');
    }

    await client.query('COMMIT');
    return activateRes.rows[0];
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function findLicenseByKey(licenseKey, { forUpdate = false } = {}) {
  const sql = `SELECT * FROM licenses WHERE license_key = $1 ${forUpdate ? 'FOR UPDATE' : ''}`;
  const res = await pool.query(sql, [licenseKey]);
  return res.rows[0] || null;
}

async function markLicenseExpired(licenseId) {
  await updateLicenseStatus(licenseId, 'VENCIDA');
}

async function extendLicenseDays(licenseId, extraDays) {
  const days = Math.floor(Number(extraDays));
  if (!Number.isFinite(days) || days <= 0) {
    throw new Error('extraDays inválido');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const licRes = await client.query('SELECT * FROM licenses WHERE id = $1 FOR UPDATE', [licenseId]);
    const license = licRes.rows[0];
    if (!license) {
      await client.query('ROLLBACK');
      return null;
    }

    const now = new Date();
    // Intentar leer license_type, si no existe la columna, asumir SUSCRIPCION
    let licenseTypeForExtend = 'SUSCRIPCION';
    try {
      licenseTypeForExtend = String(license.license_type || 'SUSCRIPCION').trim().toUpperCase();
    } catch (_) {
      licenseTypeForExtend = 'SUSCRIPCION';
    }
    if (licenseTypeForExtend === 'PERMANENTE') {
      // Intentar con expires_at, degradar si no existe
      const permAttempts = [
        async () => {
          return await client.query(
            `UPDATE licenses
             SET estado = 'ACTIVA',
                 fecha_fin = NULL,
                 expires_at = NULL
             WHERE id = $1
             RETURNING *`,
            [licenseId]
          );
        },
        async () => {
          return await client.query(
            `UPDATE licenses
             SET estado = 'ACTIVA',
                 fecha_fin = NULL
             WHERE id = $1
             RETURNING *`,
            [licenseId]
          );
        }
      ];

      let permRes = null;
      let permError = null;
      for (const attempt of permAttempts) {
        try {
          permRes = await attempt();
          break;
        } catch (e) {
          permError = e;
          if (isPgMissingColumnOrTable(e)) continue;
          throw e;
        }
      }

      if (!permRes) throw permError || new Error('No se pudo actualizar licencia permanente');
      await client.query('COMMIT');
      return permRes.rows[0] || null;
    }

    // Si aún no se ha iniciado (PENDIENTE sin fecha_inicio), solo aumentamos dias_validez.
    if (!license.fecha_inicio) {
      const updRes = await client.query(
        `UPDATE licenses
         SET dias_validez = dias_validez + $2
         WHERE id = $1
         RETURNING *`,
        [licenseId, days]
      );

      await client.query('COMMIT');
      return updRes.rows[0] || null;
    }

    const currentFin = license.fecha_fin ? new Date(license.fecha_fin) : null;
    const base = currentFin && currentFin.getTime() > now.getTime() ? currentFin : now;
    const nextFin = new Date(base.getTime() + days * 24 * 60 * 60 * 1000);

    // Mantener consistencia: dias_validez debe reflejar (fecha_fin - fecha_inicio).
    const inicio = new Date(license.fecha_inicio);
    const msPerDay = 24 * 60 * 60 * 1000;
    const nextDiasValidez = Math.max(1, Math.ceil((nextFin.getTime() - inicio.getTime()) / msPerDay));

    // Si estaba vencida y ahora la fecha_fin queda en el futuro, reactivar.
    const nextEstado = license.estado === 'VENCIDA' ? 'ACTIVA' : license.estado;

    // Intentar UPDATE con expires_at, degradar si no existe
    const extendAttempts = [
      async () => {
        return await client.query(
          `UPDATE licenses
           SET fecha_fin = $2,
               expires_at = $2,
               dias_validez = $3,
               estado = $4
           WHERE id = $1
           RETURNING *`,
          [licenseId, nextFin, nextDiasValidez, nextEstado]
        );
      },
      async () => {
        return await client.query(
          `UPDATE licenses
           SET fecha_fin = $2,
               dias_validez = $3,
               estado = $4
           WHERE id = $1
           RETURNING *`,
          [licenseId, nextFin, nextDiasValidez, nextEstado]
        );
      }
    ];

    let extendRes = null;
    let extendError = null;
    for (const attempt of extendAttempts) {
      try {
        extendRes = await attempt();
        break;
      } catch (e) {
        extendError = e;
        if (isPgMissingColumnOrTable(e)) continue;
        throw e;
      }
    }

    if (!extendRes) throw extendError || new Error('No se pudo extender la licencia');
    await client.query('COMMIT');
    return extendRes.rows[0] || null;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

module.exports = {
  createLicenseWithKey,
  listLicenses,
  getLicenseById,
  updateLicenseStatus,
  deleteLicense,
  updateLicense,
  activateLicenseManually,
  findLicenseByKey,
  markLicenseExpired,
  extendLicenseDays
};
