const { pool } = require('../../db/pool');
const { validateLicenseAndResolveCompany } = require('../sync/sync.service');

function asTrimmed(value) {
  const v = String(value ?? '').trim();
  return v || '';
}

function httpError(status, code, message) {
  const err = new Error(message || code);
  err.status = status;
  err.code = code;
  return err;
}

async function resolveContextFromHeaders(req) {
  const licenseKey = asTrimmed(req.headers['x-license-key']);
  const deviceId = asTrimmed(req.headers['x-device-id']);
  const ctx = await validateLicenseAndResolveCompany(licenseKey, deviceId);
  return { ...ctx, deviceId, licenseKey };
}

async function pushBackup({ companyId, deviceId, backupJson }) {
  if (!backupJson || typeof backupJson !== 'object') {
    throw httpError(400, 'BAD_REQUEST', 'Body JSON requerido');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const insertRes = await client.query(
      `INSERT INTO backups (company_id, device_id, backup_json)
       VALUES ($1, $2, $3)
       RETURNING id, created_at`,
      [companyId, deviceId, backupJson]
    );

    // Retención: máximo 10 backups por empresa.
    await client.query(
      `DELETE FROM backups
       WHERE id IN (
         SELECT id
         FROM backups
         WHERE company_id = $1
         ORDER BY created_at DESC
         OFFSET 10
       )`,
      [companyId]
    );

    await client.query('COMMIT');

    return {
      id: insertRes.rows[0].id,
      created_at: insertRes.rows[0].created_at
    };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function pullLatestBackup({ companyId, deviceId }) {
  const res = await pool.query(
    `SELECT id, company_id, device_id, backup_json, created_at
     FROM backups
     WHERE company_id = $1 AND device_id = $2
     ORDER BY created_at DESC
     LIMIT 1`,
    [companyId, deviceId]
  );

  return res.rows[0] || null;
}

async function pullLatestBackupForCompany({ companyId }) {
  const res = await pool.query(
    `SELECT id, company_id, device_id, backup_json, created_at
     FROM backups
     WHERE company_id = $1
     ORDER BY created_at DESC
     LIMIT 1`,
    [companyId]
  );

  return res.rows[0] || null;
}

async function listBackupHistory({ companyId, deviceId, limit = 50 }) {
  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 200);

  const res = await pool.query(
    `SELECT id, device_id, created_at
     FROM backups
     WHERE company_id = $1 AND device_id = $2
     ORDER BY created_at DESC
     LIMIT $3`,
    [companyId, deviceId, safeLimit]
  );

  return res.rows;
}

module.exports = {
  resolveContextFromHeaders,
  pushBackup,
  pullLatestBackup,
  pullLatestBackupForCompany,
  listBackupHistory
};
