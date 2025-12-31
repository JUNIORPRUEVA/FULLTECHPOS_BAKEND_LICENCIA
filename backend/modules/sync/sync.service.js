const { pool } = require('../../db/pool');
const { SYNC_TABLES } = require('./syncTables');

function parseIsoOrNull(value) {
  const v = String(value || '').trim();
  if (!v) return null;
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  return d;
}

function asTrimmed(value) {
  const v = String(value ?? '').trim();
  return v || '';
}

function asBool(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const v = String(value ?? '').trim().toLowerCase();
  return v === 'true' || v === '1' || v === 'yes';
}

function httpError(status, code, message) {
  const err = new Error(message || code);
  err.status = status;
  err.code = code;
  return err;
}

function isExpiredByDate(license, now) {
  if (!license.fecha_fin) return false;
  return new Date(license.fecha_fin).getTime() < now.getTime();
}

async function validateLicenseAndResolveCompany(licenseKey, deviceId) {
  const key = asTrimmed(licenseKey);
  const device = asTrimmed(deviceId);

  if (!key || !device) {
    throw httpError(400, 'BAD_REQUEST', 'x-license-key y x-device-id son requeridos');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const licRes = await client.query('SELECT * FROM licenses WHERE license_key = $1 FOR UPDATE', [key]);
    const license = licRes.rows[0];
    if (!license) {
      await client.query('ROLLBACK');
      throw httpError(404, 'NOT_FOUND', 'Licencia no encontrada');
    }

    // Debe existir una activación ACTIVA para ese device.
    const actRes = await client.query(
      `SELECT * FROM license_activations
       WHERE license_id = $1 AND device_id = $2`,
      [license.id, device]
    );
    const activation = actRes.rows[0];

    if (!activation || activation.estado !== 'ACTIVA') {
      await client.query('ROLLBACK');
      throw httpError(403, 'LICENSE_NOT_ACTIVE', 'Licencia no activa para este dispositivo');
    }

    await client.query('UPDATE license_activations SET last_check_at = now() WHERE id = $1', [activation.id]);

    const now = new Date();

    if (license.estado === 'BLOQUEADA') {
      await client.query('ROLLBACK');
      throw httpError(403, 'BLOCKED', 'Licencia bloqueada');
    }

    if (license.estado === 'VENCIDA' || isExpiredByDate(license, now)) {
      if (license.estado !== 'VENCIDA') {
        await client.query(`UPDATE licenses SET estado = 'VENCIDA' WHERE id = $1`, [license.id]);
      }
      await client.query('COMMIT');
      throw httpError(403, 'EXPIRED', 'Licencia vencida');
    }

    // Normalizar a ACTIVA si está vigente
    if (license.estado !== 'ACTIVA') {
      await client.query(`UPDATE licenses SET estado = 'ACTIVA' WHERE id = $1`, [license.id]);
    }

    // Resolver company_id
    const relRes = await client.query(
      `SELECT company_id
       FROM company_licenses
       WHERE license_id = $1
       LIMIT 1`,
      [license.id]
    );

    const companyId = relRes.rows[0]?.company_id;
    if (!companyId) {
      await client.query('ROLLBACK');
      throw httpError(403, 'COMPANY_NOT_LINKED', 'La licencia no está vinculada a una empresa');
    }

    await client.query('COMMIT');
    return { licenseId: license.id, companyId, status: 'ACTIVA' };
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {
      // ignore
    }
    throw e;
  } finally {
    client.release();
  }
}

function getSyncTable(name) {
  return SYNC_TABLES.find((t) => t.name === name) || null;
}

function sanitizeRecord(tableDef, raw) {
  const record = raw && typeof raw === 'object' ? raw : {};

  const id = record[tableDef.idColumn];
  if (id === undefined || id === null || id === '') {
    throw httpError(400, 'BAD_RECORD', `Falta ${tableDef.name}.${tableDef.idColumn}`);
  }

  const updatedAt = parseIsoOrNull(record.updated_at);
  const isDeleted = asBool(record.is_deleted);

  const business = {};
  for (const col of tableDef.businessColumns) {
    if (record[col] !== undefined) business[col] = record[col];
  }

  return { id, updatedAt, isDeleted, business };
}

async function upsertRecords({ companyId, tableName, records }) {
  const tableDef = getSyncTable(tableName);
  if (!tableDef) throw httpError(400, 'UNKNOWN_TABLE', `Tabla no soportada: ${tableName}`);

  const summary = { inserted: 0, updated: 0, deleted: 0, skipped: 0 };

  // Procesar en transacción
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    for (const raw of records || []) {
      const { id, updatedAt, isDeleted, business } = sanitizeRecord(tableDef, raw);

      // Always require updated_at for conflict resolution.
      const effectiveUpdatedAt = updatedAt || new Date();

      const cols = [tableDef.idColumn, ...Object.keys(business), 'is_deleted', 'updated_at'];
      const values = [id, ...Object.values(business), isDeleted, effectiveUpdatedAt];

      const colSql = cols.map((c) => `"${c}"`).join(', ');
      const paramSql = values.map((_, idx) => `$${idx + 2}`).join(', ');

      const conflictTarget = `(company_id, ${tableDef.idColumn})`;

      // Update columns on conflict
      const setCols = [...Object.keys(business), 'is_deleted', 'updated_at'];
      const setSql = setCols
        .map((c) => `"${c}" = EXCLUDED."${c}"`)
        .join(', ');

      const whereSql = isDeleted
        ? 'TRUE'
        : `(${tableDef.name}.updated_at IS NULL OR EXCLUDED.updated_at > ${tableDef.name}.updated_at)`;

      const sql = `
        INSERT INTO ${tableDef.name} (company_id, ${colSql})
        VALUES ($1, ${paramSql})
        ON CONFLICT ${conflictTarget}
        DO UPDATE SET ${setSql}
        WHERE ${whereSql}
        RETURNING xmax = 0 AS inserted, is_deleted;
      `;

      const res = await client.query(sql, [companyId, ...values]);

      if (res.rowCount === 0) {
        summary.skipped += 1;
        continue;
      }

      const row = res.rows[0];
      if (row.inserted) summary.inserted += 1;
      else summary.updated += 1;
      if (row.is_deleted) summary.deleted += 1;
    }

    await client.query('COMMIT');
    return summary;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function pullUpdates({ companyId, lastSyncAt }) {
  const last = parseIsoOrNull(lastSyncAt) || new Date(0);

  const tables = {};
  for (const t of SYNC_TABLES) {
    const res = await pool.query(
      `SELECT *
       FROM ${t.name}
       WHERE company_id = $1
         AND updated_at > $2
       ORDER BY updated_at ASC`,
      [companyId, last]
    );
    tables[t.name] = res.rows;
  }

  return { server_time: new Date().toISOString(), tables };
}

async function logSync({ companyId, licenseId, deviceId, direction, lastSyncAt, summary }) {
  await pool.query(
    `INSERT INTO sync_logs (company_id, license_id, device_id, direction, last_sync_at, summary)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [companyId, licenseId, deviceId, direction, lastSyncAt ? new Date(lastSyncAt) : null, summary || null]
  );
}

module.exports = {
  validateLicenseAndResolveCompany,
  upsertRecords,
  pullUpdates,
  logSync
};
