const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { pool } = require('../db/pool');
const { getEvolutionConfig } = require('./evolutionConfigService');
const { sendPasswordResetCode } = require('./evolutionApiService');

function normalizeUsername(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeBusinessId(value) {
  return String(value || '').trim();
}

function hashCode(code) {
  return crypto.createHash('sha256').update(String(code)).digest('hex');
}

function normalizeSupportToken(value) {
  return String(value || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
}

function generateCode() {
  return String(crypto.randomInt(100000, 999999));
}

function generateSupportToken() {
  const raw = crypto.randomBytes(16).toString('hex').toUpperCase();
  return raw.match(/.{1,4}/g).join('-');
}

function getJwtSecret() {
  const secret = String(process.env.JWT_SECRET || '').trim();
  if (secret.length >= 16) return secret;
  return 'dev-jwt-secret-change-me';
}

async function findCustomerByBusinessId(client, businessId) {
  const res = await client.query(
    `SELECT id, business_id, nombre_negocio, contacto_telefono
     FROM customers
     WHERE business_id = $1
     LIMIT 1`,
    [businessId]
  );
  return res.rows[0] || null;
}

async function createResetRequest({ businessId, username }) {
  const normalizedBusinessId = normalizeBusinessId(businessId);
  const normalizedUsername = normalizeUsername(username);
  if (!normalizedBusinessId) {
    const err = new Error('business_id es requerido');
    err.status = 400;
    throw err;
  }
  if (!normalizedUsername) {
    const err = new Error('username es requerido');
    err.status = 400;
    throw err;
  }

  const config = await getEvolutionConfig();
  if (!config.enabled) {
    const err = new Error('Recuperación no disponible: Evolution está deshabilitada');
    err.status = 503;
    throw err;
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const customer = await findCustomerByBusinessId(client, normalizedBusinessId);
    if (!customer) {
      await client.query('ROLLBACK');
      const err = new Error('Negocio no encontrado para recuperación');
      err.status = 404;
      throw err;
    }

    const phone = String(customer.contacto_telefono || '').replace(/[^0-9]/g, '');
    if (!phone) {
      await client.query('ROLLBACK');
      const err = new Error('El negocio no tiene teléfono configurado para recuperación');
      err.status = 400;
      throw err;
    }

    const ttlMinutes = Math.max(1, Number(config.otp_ttl_minutes || 10));
    const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
    const code = generateCode();
    const codeHash = hashCode(code);

    // Invalida códigos anteriores pendientes para este negocio/usuario.
    await client.query(
      `UPDATE password_reset_requests
       SET consumed_at = now(), updated_at = now()
       WHERE business_id = $1
         AND username = $2
         AND consumed_at IS NULL`,
      [normalizedBusinessId, normalizedUsername]
    );

    const insertRes = await client.query(
      `INSERT INTO password_reset_requests (
        business_id,
        username,
        phone,
        code_hash,
        code_expires_at,
        attempts,
        max_attempts,
        consumed_at,
        created_at,
        updated_at
      ) VALUES ($1, $2, $3, $4, $5, 0, 5, NULL, now(), now())
      RETURNING id, code_expires_at`,
      [normalizedBusinessId, normalizedUsername, phone, codeHash, expiresAt]
    );

    const request = insertRes.rows[0];

    await sendPasswordResetCode({
      toPhone: phone,
      code
    });

    await client.query('COMMIT');

    return {
      requestId: request.id,
      expiresAt: request.code_expires_at,
      ttlMinutes
    };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    throw error;
  } finally {
    client.release();
  }
}

async function confirmResetCode({ businessId, username, requestId, code }) {
  const normalizedBusinessId = normalizeBusinessId(businessId);
  const normalizedUsername = normalizeUsername(username);
  const normalizedRequestId = String(requestId || '').trim();
  const normalizedCode = String(code || '').replace(/[^0-9]/g, '');

  if (!normalizedBusinessId || !normalizedUsername || !normalizedRequestId || !normalizedCode) {
    const err = new Error('business_id, username, request_id y code son requeridos');
    err.status = 400;
    throw err;
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const res = await client.query(
      `SELECT id, business_id, username, code_hash, code_expires_at,
              attempts, max_attempts, consumed_at
       FROM password_reset_requests
       WHERE id = $1
         AND business_id = $2
         AND username = $3
       LIMIT 1
       FOR UPDATE`,
      [normalizedRequestId, normalizedBusinessId, normalizedUsername]
    );

    if (!res.rows || res.rows.length === 0) {
      await client.query('ROLLBACK');
      const err = new Error('Solicitud de reseteo no encontrada');
      err.status = 404;
      throw err;
    }

    const row = res.rows[0];
    if (row.consumed_at) {
      await client.query('ROLLBACK');
      const err = new Error('El código ya fue utilizado');
      err.status = 409;
      throw err;
    }

    const expiresAt = new Date(row.code_expires_at);
    if (Number.isNaN(expiresAt.getTime()) || Date.now() > expiresAt.getTime()) {
      await client.query(
        'UPDATE password_reset_requests SET consumed_at = now(), updated_at = now() WHERE id = $1',
        [row.id]
      );
      await client.query('COMMIT');
      const err = new Error('El código expiró, solicita uno nuevo');
      err.status = 410;
      throw err;
    }

    if (Number(row.attempts || 0) >= Number(row.max_attempts || 5)) {
      await client.query(
        'UPDATE password_reset_requests SET consumed_at = now(), updated_at = now() WHERE id = $1',
        [row.id]
      );
      await client.query('COMMIT');
      const err = new Error('Demasiados intentos, solicita un código nuevo');
      err.status = 429;
      throw err;
    }

    const incomingHash = hashCode(normalizedCode);
    if (incomingHash !== String(row.code_hash || '')) {
      await client.query(
        'UPDATE password_reset_requests SET attempts = attempts + 1, updated_at = now() WHERE id = $1',
        [row.id]
      );
      await client.query('COMMIT');
      const err = new Error('Código inválido');
      err.status = 400;
      throw err;
    }

    await client.query(
      'UPDATE password_reset_requests SET consumed_at = now(), updated_at = now() WHERE id = $1',
      [row.id]
    );

    await client.query('COMMIT');

    const resetProof = jwt.sign(
      {
        businessId: normalizedBusinessId,
        username: normalizedUsername,
        requestId: normalizedRequestId,
        purpose: 'local_password_reset'
      },
      getJwtSecret(),
      {
        expiresIn: '10m'
      }
    );

    return {
      ok: true,
      resetProof,
      expiresIn: '10m'
    };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    throw error;
  } finally {
    client.release();
  }
}

async function createSupportResetToken({ businessId, username, issuedBy }) {
  const normalizedBusinessId = normalizeBusinessId(businessId);
  const normalizedUsername = normalizeUsername(username || 'admin');
  const normalizedIssuedBy = String(issuedBy || '').trim() || 'support';

  if (!normalizedBusinessId) {
    const err = new Error('business_id es requerido');
    err.status = 400;
    throw err;
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const customer = await findCustomerByBusinessId(client, normalizedBusinessId);
    if (!customer) {
      await client.query('ROLLBACK');
      const err = new Error('Negocio no encontrado para recuperación');
      err.status = 404;
      throw err;
    }

    const ttlMinutes = 15;
    const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
    const token = generateSupportToken();
    const tokenHash = hashCode(normalizeSupportToken(token));

    await client.query(
      `UPDATE support_reset_tokens
       SET consumed_at = now(), updated_at = now()
       WHERE business_id = $1
         AND username = $2
         AND consumed_at IS NULL`,
      [normalizedBusinessId, normalizedUsername]
    );

    await client.query(
      `INSERT INTO support_reset_tokens (
        business_id,
        username,
        token_hash,
        token_expires_at,
        issued_by,
        consumed_at,
        created_at,
        updated_at
      ) VALUES ($1, $2, $3, $4, $5, NULL, now(), now())`,
      [normalizedBusinessId, normalizedUsername, tokenHash, expiresAt, normalizedIssuedBy]
    );

    await client.query('COMMIT');

    return {
      token,
      ttlMinutes,
      expiresAt
    };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    throw error;
  } finally {
    client.release();
  }
}

async function confirmSupportToken({ businessId, username, token }) {
  const normalizedBusinessId = normalizeBusinessId(businessId);
  const normalizedUsername = normalizeUsername(username || 'admin');
  const normalizedToken = normalizeSupportToken(token);

  if (!normalizedBusinessId || !normalizedToken) {
    const err = new Error('business_id y token son requeridos');
    err.status = 400;
    throw err;
  }

  const tokenHash = hashCode(normalizedToken);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const res = await client.query(
      `SELECT id, token_expires_at, consumed_at
       FROM support_reset_tokens
       WHERE business_id = $1
         AND username = $2
         AND token_hash = $3
       ORDER BY created_at DESC
       LIMIT 1
       FOR UPDATE`,
      [normalizedBusinessId, normalizedUsername, tokenHash]
    );

    if (!res.rows || res.rows.length === 0) {
      await client.query('ROLLBACK');
      const err = new Error('Token inválido');
      err.status = 400;
      throw err;
    }

    const row = res.rows[0];
    if (row.consumed_at) {
      await client.query('ROLLBACK');
      const err = new Error('El token ya fue utilizado');
      err.status = 409;
      throw err;
    }

    const expiresAt = new Date(row.token_expires_at);
    if (Number.isNaN(expiresAt.getTime()) || Date.now() > expiresAt.getTime()) {
      await client.query(
        'UPDATE support_reset_tokens SET consumed_at = now(), updated_at = now() WHERE id = $1',
        [row.id]
      );
      await client.query('COMMIT');
      const err = new Error('El token expiró, solicita uno nuevo a soporte');
      err.status = 410;
      throw err;
    }

    await client.query(
      'UPDATE support_reset_tokens SET consumed_at = now(), updated_at = now() WHERE id = $1',
      [row.id]
    );

    await client.query('COMMIT');

    const resetProof = jwt.sign(
      {
        businessId: normalizedBusinessId,
        username: normalizedUsername,
        purpose: 'manual_support_password_reset'
      },
      getJwtSecret(),
      {
        expiresIn: '10m'
      }
    );

    return {
      ok: true,
      resetProof,
      expiresIn: '10m'
    };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  createResetRequest,
  confirmResetCode,
  createSupportResetToken,
  confirmSupportToken
};
