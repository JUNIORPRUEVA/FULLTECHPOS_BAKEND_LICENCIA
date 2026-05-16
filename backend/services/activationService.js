const { pool } = require('../db/pool');
const activationsModel = require('../models/activationsModel');
const auditLogService = require('./auditLogService');

const VALID_DEVICE_TYPES = new Set(['pc', 'movil', 'mobile', 'tablet']);
const BLOCKING_SUBSCRIPTION_STATUSES = new Set([
  'PENDING_PAYMENT',
  'GRACE',
  'EXPIRED',
  'CANCELLED',
  'PAST_DUE',
  'SUSPENDED',
  'CANCELLED',
  'EXPIRED'
]);

function httpError(statusCode, code, message) {
  const error = new Error(message || code);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

function normalizeText(value, { max = 300 } = {}) {
  const raw = String(value || '').trim();
  if (!raw) return null;
  return raw.slice(0, max);
}

function normalizeDeviceType(value) {
  const raw = String(value || '').trim().toLowerCase();
  if (raw === 'móvil' || raw === 'movil' || raw === 'mobile') return 'movil';
  if (raw === 'pc' || raw === 'desktop' || raw === 'windows') return 'pc';
  if (raw === 'tablet') return 'tablet';
  return null;
}

function normalizeSubscriptionStatus(value) {
  const raw = String(value || '').trim();
  if (!raw) return null;
  const upper = raw.toUpperCase();
  if (upper === 'ACTIVE' || upper === 'TRIAL' || upper === 'LIFETIME') return 'ACTIVE';
  if (upper === 'PAST_DUE') return 'PENDING_PAYMENT';
  if (upper === 'SUSPENDED') return 'EXPIRED';
  if (upper === 'CANCELLED') return 'CANCELLED';
  if (upper === 'EXPIRED') return 'EXPIRED';
  if (upper === 'GRACE') return 'GRACE';
  if (upper === 'PENDING_PAYMENT') return 'PENDING_PAYMENT';
  return upper;
}

function isPast(value, now = new Date()) {
  if (!value) return false;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return false;
  return date.getTime() < now.getTime();
}

function clientIp(req) {
  const forwarded = String(req?.headers?.['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || req?.ip || req?.socket?.remoteAddress || null;
}

async function findLicenseForActivation(licenseKey, client) {
  const res = await client.query(
    `SELECT *
     FROM licenses
     WHERE license_key = $1
     LIMIT 1
     FOR UPDATE`,
    [licenseKey]
  );
  return res.rows[0] || null;
}

async function findSubscriptionForLicense(license, client) {
  const params = [];
  const where = [];

  if (license.subscription_id) {
    params.push(license.subscription_id);
    where.push(`cs.id = $${params.length}`);
  }

  params.push(license.id);
  where.push(`cs.license_id = $${params.length}`);

  const res = await client.query(
    `SELECT cs.*, pp.billing_period, pp.device_limit, pp.name AS plan_name
     FROM company_subscriptions cs
     LEFT JOIN product_plans pp ON pp.id = cs.plan_id
     WHERE ${where.join(' OR ')}
     ORDER BY cs.updated_at DESC, cs.created_at DESC
     LIMIT 1`,
    params
  );
  return res.rows[0] || null;
}

function resolveLicenseType(license, subscription) {
  const licenseType = String(license.license_type || '').trim().toUpperCase();
  if (licenseType === 'PERMANENTE' || licenseType === 'SUSCRIPCION') return licenseType;
  if (subscription?.billing_period === 'lifetime') return 'PERMANENTE';
  return license.fecha_fin || license.expires_at || subscription ? 'SUSCRIPCION' : 'PERMANENTE';
}

function validateLicenseAccess(license, subscription, now = new Date()) {
  if (!license) throw httpError(404, 'LICENSE_NOT_FOUND', 'Licencia no encontrada');

  const licenseState = String(license.estado || '').trim().toUpperCase();
  if (licenseState !== 'ACTIVA') {
    throw httpError(403, 'LICENSE_NOT_ACTIVE', 'La licencia no está activa');
  }

  const licenseType = resolveLicenseType(license, subscription);
  if (licenseType === 'SUSCRIPCION') {
    const expiration = license.expires_at || license.fecha_fin || subscription?.end_date || subscription?.renewal_date;
    if (isPast(expiration, now)) {
      throw httpError(403, 'LICENSE_EXPIRED', 'La licencia está vencida');
    }

    const subscriptionStatus = normalizeSubscriptionStatus(subscription?.status);
    if (subscriptionStatus && BLOCKING_SUBSCRIPTION_STATUSES.has(subscriptionStatus)) {
      throw httpError(402, 'SUBSCRIPTION_PAYMENT_REQUIRED', 'La suscripción tiene pagos pendientes o deuda');
    }
  }

  return { licenseType };
}

async function blockLicenseActivations(licenseId, client, req, reason) {
  const blocked = await activationsModel.blockActivationsForLicense(licenseId, { client });
  if (blocked.length) {
    await auditLogService.log({
      target_type: 'license',
      target_id: licenseId,
      action: 'activation.auto_blocked',
      after_data: { reason, blocked_count: blocked.length }
    }, { client, req });
  }
  return blocked;
}

function mapActivationResponse({ activation, license, subscription, usedDevices }) {
  return {
    ok: true,
    activation: {
      id: activation.id,
      license_id: activation.license_id,
      device_id: activation.device_id,
      device_name: activation.device_name || null,
      device_type: activation.device_type || null,
      ip_address: activation.ip_address || null,
      created_at: activation.created_at || activation.activated_at,
      last_seen_at: activation.last_seen_at || activation.last_check_at,
      status: activation.status
    },
    license: {
      id: license.id,
      estado: license.estado,
      license_type: resolveLicenseType(license, subscription),
      max_devices: Number(license.max_dispositivos || 0) || null,
      expires_at: license.expires_at || license.fecha_fin || null
    },
    subscription: subscription ? {
      id: subscription.id,
      status: subscription.status,
      next_payment_date: subscription.next_payment_date || null
    } : null,
    limits: {
      max_devices: Number(license.max_dispositivos || 0) || null,
      used_devices: usedDevices
    },
    can_access: activation.status === 'ACTIVE'
  };
}

async function activate(payload, { req } = {}) {
  const licenseKey = normalizeText(payload?.license_key, { max: 200 });
  const deviceId = normalizeText(payload?.device_id, { max: 200 });
  const deviceName = normalizeText(payload?.device_name, { max: 200 });
  const deviceType = normalizeDeviceType(payload?.device_type);
  const ipAddress = clientIp(req);

  if (!licenseKey) throw httpError(400, 'LICENSE_KEY_REQUIRED', 'license_key es requerido');
  if (!deviceId) throw httpError(400, 'DEVICE_ID_REQUIRED', 'device_id es requerido');
  if (!deviceName) throw httpError(400, 'DEVICE_NAME_REQUIRED', 'device_name es requerido');
  if (!deviceType) throw httpError(400, 'DEVICE_TYPE_INVALID', 'device_type debe ser pc, movil o tablet');

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');

    const license = await findLicenseForActivation(licenseKey, client);
    const subscription = license ? await findSubscriptionForLicense(license, client) : null;

    try {
      validateLicenseAccess(license, subscription);
    } catch (error) {
      if (license?.id) await blockLicenseActivations(license.id, client, req, error.code || 'license_invalid');
      await client.query('COMMIT');
      committed = true;
      throw error;
    }

    const sameDeviceRows = await activationsModel.getActivationByDevice({ device_id: deviceId, client });
    const activeOnAnotherLicense = sameDeviceRows.find((row) => row.license_id !== license.id);
    if (activeOnAnotherLicense) {
      throw httpError(409, 'DEVICE_ALREADY_ACTIVATED', 'Este dispositivo ya está activo en otra licencia');
    }

    const existing = await activationsModel.getActivationByLicenseAndDevice({
      license_id: license.id,
      device_id: deviceId,
      client
    });

    if (existing?.status === 'REVOKED') {
      throw httpError(403, 'ACTIVATION_REVOKED', 'La activación de este dispositivo fue revocada');
    }
    if (existing?.status === 'BLOCKED') {
      throw httpError(403, 'ACTIVATION_BLOCKED', 'La activación de este dispositivo está bloqueada');
    }

    const activeCount = await activationsModel.countActiveActivations({
      license_id: license.id,
      exclude_device_id: deviceId,
      client
    });
    const maxDevices = Number(license.max_dispositivos || 0);
    if (maxDevices > 0 && activeCount >= maxDevices && !existing) {
      throw httpError(409, 'MAX_DEVICES_REACHED', 'Límite de dispositivos alcanzado');
    }

    const activation = existing
      ? await activationsModel.activateExisting({
          activation_id: existing.id,
          device_name: deviceName,
          device_type: deviceType,
          ip_address: ipAddress,
          client
        })
      : await activationsModel.createActivation({
          license_id: license.id,
          device_id: deviceId,
          device_name: deviceName,
          device_type: deviceType,
          ip_address: ipAddress,
          client
        });

    const usedDevices = await activationsModel.countActiveActivations({ license_id: license.id, client });

    await auditLogService.log({
      company_id: license.company_id || subscription?.company_id || null,
      product_id: license.product_id || subscription?.product_id || null,
      project_id: license.project_id || subscription?.project_id || null,
      target_type: 'activation',
      target_id: activation.id,
      action: existing ? 'activation.heartbeat_activate' : 'activation.create',
      after_data: {
        license_id: license.id,
        device_id: 'provided',
        device_type: deviceType,
        status: activation.status
      }
    }, { client, req });

    await client.query('COMMIT');
    committed = true;
    return mapActivationResponse({ activation, license, subscription, usedDevices });
  } catch (error) {
    if (!committed) await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function heartbeat(payload, { req } = {}) {
  const deviceId = normalizeText(payload?.device_id, { max: 200 });
  const ipAddress = clientIp(req);
  if (!deviceId) throw httpError(400, 'DEVICE_ID_REQUIRED', 'device_id es requerido');

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');

    const rows = await activationsModel.getActivationByDevice({ device_id: deviceId, client, activeOnly: false });
    if (!rows.length) throw httpError(404, 'ACTIVATION_NOT_FOUND', 'Activación no encontrada');
    if (rows.length > 1) throw httpError(409, 'DEVICE_NOT_UNIQUE', 'device_id activo en más de una licencia');

    const activationRow = rows[0];
    if (activationRow.status === 'REVOKED') {
      throw httpError(403, 'ACTIVATION_REVOKED', 'La activación fue revocada');
    }
    if (activationRow.status === 'BLOCKED') {
      throw httpError(403, 'ACTIVATION_BLOCKED', 'La activación está bloqueada');
    }

    const license = await findLicenseForActivation(activationRow.license_key, client);
    const subscription = license ? await findSubscriptionForLicense(license, client) : null;

    try {
      validateLicenseAccess(license, subscription);
    } catch (error) {
      if (license?.id) await blockLicenseActivations(license.id, client, req, error.code || 'license_invalid');
      await client.query('COMMIT');
      committed = true;
      throw error;
    }

    if (activationRow.status !== 'ACTIVE') {
      throw httpError(403, 'ACTIVATION_NOT_ACTIVE', 'La activación no está activa');
    }

    const activation = await activationsModel.touchActivation({
      activation_id: activationRow.id,
      ip_address: ipAddress,
      client
    });
    const usedDevices = await activationsModel.countActiveActivations({ license_id: license.id, client });

    await client.query('COMMIT');
    committed = true;
    return mapActivationResponse({ activation, license, subscription, usedDevices });
  } catch (error) {
    if (!committed) await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function revoke(payload, { req } = {}) {
  const licenseKey = normalizeText(payload?.license_key, { max: 200 });
  const deviceId = normalizeText(payload?.device_id, { max: 200 });
  if (!licenseKey) throw httpError(400, 'LICENSE_KEY_REQUIRED', 'license_key es requerido');
  if (!deviceId) throw httpError(400, 'DEVICE_ID_REQUIRED', 'device_id es requerido');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const license = await findLicenseForActivation(licenseKey, client);
    if (!license) throw httpError(404, 'LICENSE_NOT_FOUND', 'Licencia no encontrada');

    const existing = await activationsModel.getActivationByLicenseAndDevice({
      license_id: license.id,
      device_id: deviceId,
      client
    });
    if (!existing) throw httpError(404, 'ACTIVATION_NOT_FOUND', 'Activación no encontrada');

    const activation = await activationsModel.revokeActivation(existing.id, { client });
    await auditLogService.log({
      target_type: 'activation',
      target_id: activation.id,
      action: 'activation.revoke_public',
      after_data: { device_id: 'provided', status: activation.status }
    }, { client, req });

    await client.query('COMMIT');
    return { ok: true, activation };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  activate,
  heartbeat,
  revoke,
  blockLicenseActivations,
  httpError
};
