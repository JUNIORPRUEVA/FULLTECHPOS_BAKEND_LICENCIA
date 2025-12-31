const { pool } = require('../db/pool');

async function createLicenseWithKey({
  customer_id,
  license_key,
  tipo,
  dias_validez,
  max_dispositivos,
  notas
}) {
  const result = await pool.query(
    `INSERT INTO licenses (customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, notas)
     VALUES ($1, $2, $3, $4, $5, 'PENDIENTE', $6)
     RETURNING *`,
    [customer_id || null, license_key, tipo, dias_validez, max_dispositivos, notas || null]
  );
  return result.rows[0];
}

async function listLicenses({ limit, offset, customer_id, tipo, estado }) {
  const where = [];
  const params = [];

  if (customer_id) {
    params.push(customer_id);
    where.push(`l.customer_id = $${params.length}`);
  }
  if (tipo) {
    params.push(tipo);
    where.push(`l.tipo = $${params.length}`);
  }
  if (estado) {
    params.push(estado);
    where.push(`l.estado = $${params.length}`);
  }

  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const totalRes = await pool.query(
    `SELECT COUNT(*)::int AS total
     FROM licenses l
     ${whereSql}`,
    params
  );
  const total = totalRes.rows[0]?.total || 0;

  params.push(limit);
  params.push(offset);

  const rowsRes = await pool.query(
    `SELECT l.*, c.nombre_negocio
     FROM licenses l
     LEFT JOIN customers c ON c.id = l.customer_id
     ${whereSql}
     ORDER BY l.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return { total, licenses: rowsRes.rows };
}

async function getLicenseById(licenseId) {
  const licRes = await pool.query(
    `SELECT l.*, c.nombre_negocio
     FROM licenses l
     LEFT JOIN customers c ON c.id = l.customer_id
     WHERE l.id = $1`,
    [licenseId]
  );
  const license = licRes.rows[0];
  if (!license) return null;

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
  const res = await pool.query(
    `UPDATE licenses
     SET estado = $2
     WHERE id = $1
     RETURNING *`,
    [licenseId, estado]
  );
  return res.rows[0] || null;
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

    const nextTipo = patch.tipo != null ? patch.tipo : current.tipo;
    const nextDias = patch.dias_validez != null ? patch.dias_validez : current.dias_validez;
    const nextMax = patch.max_dispositivos != null ? patch.max_dispositivos : current.max_dispositivos;
    const nextNotas = patch.notas !== undefined ? patch.notas : current.notas;
    const nextEstado = patch.estado != null ? patch.estado : current.estado;

    let nextFechaInicio = current.fecha_inicio;
    let nextFechaFin = current.fecha_fin;

    // Reglas de fechas por cambio de estado
    if (patch.estado === 'PENDIENTE') {
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

    const updRes = await client.query(
      `UPDATE licenses
       SET tipo = $2,
           dias_validez = $3,
           max_dispositivos = $4,
           estado = $5,
           notas = $6,
           fecha_inicio = $7,
           fecha_fin = $8
       WHERE id = $1
       RETURNING *`,
      [
        licenseId,
        nextTipo,
        Number(nextDias),
        Number(nextMax),
        nextEstado,
        nextNotas,
        nextFechaInicio,
        nextFechaFin
      ]
    );

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

    const fechaFinMs = fecha_fin ? new Date(fecha_fin).getTime() : NaN;
    const isFechaFinValid = Number.isFinite(fechaFinMs);
    const isExpiredByDate = isFechaFinValid ? fechaFinMs < now.getTime() : false;

    // Activación/Desbloqueo manual debe dejar la licencia utilizable.
    // Si no tiene fechas o ya venció por fecha, rearmar un nuevo período desde ahora.
    if (!fecha_inicio || !fecha_fin || isExpiredByDate) {
      fecha_inicio = now;
      fecha_fin = new Date(now.getTime() + days * msPerDay);
    }

    const updRes = await client.query(
      `UPDATE licenses
       SET estado = 'ACTIVA', fecha_inicio = $2, fecha_fin = $3
       WHERE id = $1
       RETURNING *`,
      [licenseId, fecha_inicio, fecha_fin]
    );

    await client.query('COMMIT');
    return updRes.rows[0];
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
  await pool.query(`UPDATE licenses SET estado = 'VENCIDA' WHERE id = $1`, [licenseId]);
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

    const updRes = await client.query(
      `UPDATE licenses
       SET fecha_fin = $2,
           dias_validez = $3,
           estado = $4
       WHERE id = $1
       RETURNING *`,
      [licenseId, nextFin, nextDiasValidez, nextEstado]
    );

    await client.query('COMMIT');
    return updRes.rows[0] || null;
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
  updateLicense,
  activateLicenseManually,
  findLicenseByKey,
  markLicenseExpired,
  extendLicenseDays
};
