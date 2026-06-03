const crypto = require('crypto');
const { pool } = require('../db/pool');
const auditLogService = require('./auditLogService');

const UUID_V4_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const LEGACY_BIZ_REGEX = /^BIZ-[0-9A-F]{8,}$/i;

function normalizeBusinessId(value) {
  const normalized = String(value || '').trim();
  return normalized || null;
}

function isUuidV4BusinessId(value) {
  const normalized = normalizeBusinessId(value);
  return normalized ? UUID_V4_REGEX.test(normalized) : false;
}

function isLegacyBizBusinessId(value) {
  const normalized = normalizeBusinessId(value);
  return normalized ? LEGACY_BIZ_REGEX.test(normalized) : false;
}

function generateNewBusinessId() {
  return crypto.randomUUID();
}

function buildAuditPayload({
  event,
  source,
  action,
  reason,
  severity = 'info',
  currentBusinessId = null,
  incomingBusinessId = null,
  resolvedBusinessId = null,
  customerId = null,
  licenseId = null,
}) {
  return {
    event,
    source,
    action,
    reason,
    severity,
    currentBusinessId,
    incomingBusinessId,
    resolvedBusinessId,
    customerId,
    licenseId,
  };
}

async function emitBusinessIdAudit(entry, { req, client } = {}) {
  const payload = buildAuditPayload(entry);
  const targetId =
    payload.customerId || payload.licenseId || payload.resolvedBusinessId || 'business_id';

  try {
    await auditLogService.log(
      {
        target_type: payload.customerId ? 'customer' : payload.licenseId ? 'license' : 'other',
        target_id: String(targetId),
        action: `business_id.${payload.event}`,
        before_data: {
          currentBusinessId: payload.currentBusinessId,
          incomingBusinessId: payload.incomingBusinessId,
        },
        after_data: {
          source: payload.source,
          action: payload.action,
          reason: payload.reason,
          severity: payload.severity,
          resolvedBusinessId: payload.resolvedBusinessId,
          customerId: payload.customerId,
          licenseId: payload.licenseId,
        }
      },
      { req, client }
    );
  } catch (error) {
    console.warn('[business_id_audit] audit log fallback:', {
      message: error?.message,
      original: payload,
    });
  }

  const logLine = JSON.stringify({
    event: payload.event,
    source: payload.source,
    action: payload.action,
    reason: payload.reason,
    severity: payload.severity,
    currentBusinessId: payload.currentBusinessId,
    incomingBusinessId: payload.incomingBusinessId,
    resolvedBusinessId: payload.resolvedBusinessId,
    customerId: payload.customerId,
    licenseId: payload.licenseId,
  });

  if (payload.severity === 'critical') {
    console.error(logLine);
  } else if (payload.severity === 'warn') {
    console.warn(logLine);
  } else {
    console.info(logLine);
  }
}

async function findExistingBusinessIdUsage(businessId, { client = pool } = {}) {
  const normalized = normalizeBusinessId(businessId);
  if (!normalized) {
    return {
      customerExists: false,
      customerId: null,
      hasActiveLicense: false,
      activeLicenseId: null,
      exists: false,
    };
  }

  const result = await client.query(
    `SELECT
        c.id AS customer_id,
        EXISTS (
          SELECT 1
          FROM licenses l
          WHERE l.customer_id = c.id
            AND l.estado::text = 'ACTIVA'
            AND (l.fecha_fin IS NULL OR l.fecha_fin >= NOW())
        ) AS has_active_license,
        (
          SELECT l.id
          FROM licenses l
          WHERE l.customer_id = c.id
            AND l.estado::text = 'ACTIVA'
            AND (l.fecha_fin IS NULL OR l.fecha_fin >= NOW())
          ORDER BY l.created_at DESC
          LIMIT 1
        ) AS active_license_id
     FROM customers c
     WHERE c.business_id = $1
     LIMIT 1`,
    [normalized]
  );

  const row = result.rows[0] || null;
  return {
    customerExists: Boolean(row),
    customerId: row?.customer_id || null,
    hasActiveLicense: Boolean(row?.has_active_license),
    activeLicenseId: row?.active_license_id || null,
    exists: Boolean(row),
  };
}

async function isValidBusinessIdForExistingRecord(businessId, { client = pool } = {}) {
  const normalized = normalizeBusinessId(businessId);
  if (!normalized) return false;
  if (isUuidV4BusinessId(normalized)) return true;
  if (isLegacyBizBusinessId(normalized)) return true;

  const usage = await findExistingBusinessIdUsage(normalized, { client });
  return usage.exists;
}

function isValidBusinessIdForNewRecord(businessId) {
  return isUuidV4BusinessId(businessId);
}

async function resolveBusinessIdForNewRecord(businessId) {
  const normalized = normalizeBusinessId(businessId);
  if (!normalized) return generateNewBusinessId();
  if (!isValidBusinessIdForNewRecord(normalized)) {
    const error = new Error('business_id inválido para nuevo registro');
    error.code = 'INVALID_NEW_BUSINESS_ID';
    throw error;
  }
  return normalized;
}

async function getCustomerBusinessIdMutationContext(customerId, { client = pool } = {}) {
  const customerRes = await client.query(
    `SELECT id, business_id, nombre_negocio
     FROM customers
     WHERE id = $1
     LIMIT 1`,
    [customerId]
  );
  const customer = customerRes.rows[0] || null;
  if (!customer) return null;

  const countsRes = await client.query(
    `SELECT
        COALESCE((
          SELECT COUNT(*)::int
          FROM licenses l
          WHERE l.customer_id = $1
            AND l.estado::text = 'ACTIVA'
            AND (l.fecha_fin IS NULL OR l.fecha_fin >= NOW())
        ), 0) AS active_license_count,
        COALESCE((SELECT COUNT(*)::int FROM licenses l WHERE l.customer_id = $1), 0) AS license_count,
        COALESCE((
          SELECT COUNT(*)::int
          FROM license_activations a
          JOIN licenses l ON l.id = a.license_id
          WHERE l.customer_id = $1
        ), 0) AS activation_count,
        COALESCE((SELECT COUNT(*)::int FROM license_payment_orders p WHERE p.customer_id = $1), 0) AS payment_count`,
    [customerId]
  );

  const counts = countsRes.rows[0] || {};
  return {
    customer,
    activeLicenseCount: Number(counts.active_license_count || 0),
    licenseCount: Number(counts.license_count || 0),
    activationCount: Number(counts.activation_count || 0),
    paymentCount: Number(counts.payment_count || 0),
  };
}

function canChangeBusinessIdNormally(context, nextBusinessId) {
  const currentBusinessId = normalizeBusinessId(context?.customer?.business_id);
  const nextNormalized = normalizeBusinessId(nextBusinessId);

  if (!context) return false;
  if (!nextNormalized) return false;
  if (!currentBusinessId) return true;
  if (currentBusinessId === nextNormalized) return true;
  return false;
}

function requiresRepairMode(context, nextBusinessId) {
  const currentBusinessId = normalizeBusinessId(context?.customer?.business_id);
  const nextNormalized = normalizeBusinessId(nextBusinessId);
  if (!currentBusinessId || !nextNormalized) return false;
  if (currentBusinessId === nextNormalized) return false;
  return true;
}

function canRepairBusinessId(context) {
  if (!context) return false;
  return true;
}

function hasProtectedCustomerActivity(context) {
  if (!context) return false;
  return (
    context.activeLicenseCount > 0 ||
    context.licenseCount > 0 ||
    context.activationCount > 0 ||
    context.paymentCount > 0
  );
}

async function beginBusinessIdRepairSession(client) {
  await client.query(`SELECT set_config('app.allow_business_id_repair', '1', true)`);
}

module.exports = {
  normalizeBusinessId,
  isUuidV4BusinessId,
  isLegacyBizBusinessId,
  isValidBusinessIdForExistingRecord,
  isValidBusinessIdForNewRecord,
  resolveBusinessIdForNewRecord,
  findExistingBusinessIdUsage,
  getCustomerBusinessIdMutationContext,
  canChangeBusinessIdNormally,
  requiresRepairMode,
  canRepairBusinessId,
  hasProtectedCustomerActivity,
  generateNewBusinessId,
  beginBusinessIdRepairSession,
  emitBusinessIdAudit,
};
