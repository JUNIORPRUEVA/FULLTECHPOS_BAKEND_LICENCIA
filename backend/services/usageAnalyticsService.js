const { pool } = require('../db/pool');
const usageAnalyticsModel = require('../models/usageAnalyticsModel');

const DEFAULT_EVENT_TYPE = 'app_heartbeat';
const MAX_BATCH_SIZE = 100;

function httpError(statusCode, code, message) {
  const error = new Error(message || code);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

function normalizeText(value, { max = 200, upper = false } = {}) {
  const raw = String(value || '').trim();
  if (!raw) return null;
  const sliced = raw.slice(0, max);
  return upper ? sliced.toUpperCase() : sliced;
}

function normalizeObject(value, { maxKeys = 40 } = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  const out = {};
  for (const [key, rawValue] of Object.entries(value).slice(0, maxKeys)) {
    const safeKey = String(key || '').trim().slice(0, 80);
    if (!safeKey) continue;
    if (rawValue == null || ['string', 'number', 'boolean'].includes(typeof rawValue)) {
      out[safeKey] = typeof rawValue === 'string' ? rawValue.slice(0, 500) : rawValue;
    }
  }
  return out;
}

function normalizeActiveSeconds(value) {
  const n = Math.floor(Number(value || 0));
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(86400, n);
}

function normalizeDate(value) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function clientIp(req) {
  const forwarded = String(req?.headers?.['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || req?.ip || req?.socket?.remoteAddress || null;
}

function assertIngestAllowed(req) {
  const configuredSecret = String(process.env.USAGE_INGEST_SECRET || '').trim();
  if (!configuredSecret) return;
  const provided = String(req?.headers?.['x-usage-ingest-secret'] || req?.headers?.['x-license-usage-secret'] || '').trim();
  if (provided !== configuredSecret) {
    throw httpError(401, 'USAGE_SECRET_INVALID', 'No autorizado para reportar uso');
  }
}

function normalizeUsageEvent(payload, req) {
  const appCode = normalizeText(payload?.app_code || payload?.project_code, { max: 80, upper: true });
  const deviceId = normalizeText(payload?.device_id, { max: 200 });

  if (!appCode) throw httpError(400, 'APP_CODE_REQUIRED', 'app_code o project_code es requerido');
  if (!deviceId) throw httpError(400, 'DEVICE_ID_REQUIRED', 'device_id es requerido');

  return {
    project_code: normalizeText(payload?.project_code, { max: 80, upper: true }),
    app_code: appCode,
    license_key: normalizeText(payload?.license_key, { max: 200 }),
    business_id: normalizeText(payload?.business_id, { max: 200 }),
    device_id: deviceId,
    session_id: normalizeText(payload?.session_id, { max: 200 }),
    event_type: normalizeText(payload?.event_type, { max: 80 }) || DEFAULT_EVENT_TYPE,
    feature_code: normalizeText(payload?.feature_code, { max: 80 }),
    app_version: normalizeText(payload?.app_version, { max: 80 }),
    occurred_at: normalizeDate(payload?.occurred_at || payload?.timestamp),
    active_seconds: normalizeActiveSeconds(payload?.active_seconds),
    metrics: normalizeObject(payload?.metrics || payload?.stats),
    metadata: normalizeObject(payload?.metadata),
    ip_address: clientIp(req)
  };
}

async function ingestOne(payload, { req, client }) {
  const normalized = normalizeUsageEvent(payload, req);
  const context = await usageAnalyticsModel.resolveUsageContext({
    license_key: normalized.license_key,
    business_id: normalized.business_id,
    project_code: normalized.project_code || normalized.app_code,
    client
  });

  const event = {
    ...normalized,
    project_id: context.project_id || null,
    license_id: context.license_id || null,
    customer_id: context.customer_id || null,
    business_id: context.business_id || normalized.business_id || null
  };

  const { row, subjectKey } = await usageAnalyticsModel.insertUsageEvent(event, { client });
  await usageAnalyticsModel.upsertDailyStats(event, subjectKey, { client });
  await usageAnalyticsModel.upsertFeatureStats(event, subjectKey, { client });

  return {
    id: row.id,
    subject_key: subjectKey,
    project_id: event.project_id,
    license_id: event.license_id,
    customer_id: event.customer_id,
    business_id: event.business_id,
    received_at: row.received_at
  };
}

async function ingest(payload, { req } = {}) {
  assertIngestAllowed(req);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const accepted = await ingestOne(payload || {}, { req, client });
    await client.query('COMMIT');
    return { ok: true, accepted: 1, usage: accepted };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function ingestBatch(payload, { req } = {}) {
  assertIngestAllowed(req);
  const events = Array.isArray(payload?.events) ? payload.events : [];
  if (!events.length) throw httpError(400, 'EVENTS_REQUIRED', 'events debe contener al menos un evento');
  if (events.length > MAX_BATCH_SIZE) {
    throw httpError(400, 'BATCH_TOO_LARGE', `Máximo ${MAX_BATCH_SIZE} eventos por lote`);
  }

  const client = await pool.connect();
  const accepted = [];
  try {
    await client.query('BEGIN');
    for (const event of events) {
      accepted.push(await ingestOne(event, { req, client }));
    }
    await client.query('COMMIT');
    return { ok: true, accepted: accepted.length, usage: accepted };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  ingest,
  ingestBatch,
  httpError
};
