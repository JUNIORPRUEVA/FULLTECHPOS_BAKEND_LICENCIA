const { pool } = require('../db/pool');

const SINGLETON_ID = '00000000-0000-0000-0000-000000000001';

const DEFAULT_TEMPLATE =
  'FULLPOS: Tu código para restablecer contraseña es {code}. Vence en {ttl_minutes} minutos.';

function normalizeUrl(input) {
  const value = String(input || '').trim();
  if (!value) return '';
  return value.replace(/\/+$/, '');
}

function asNullableTrimmed(input) {
  const value = String(input || '').trim();
  return value || null;
}

function asBool(value, fallback = false) {
  if (value === undefined || value === null) return fallback;
  if (typeof value === 'boolean') return value;
  const text = String(value).trim().toLowerCase();
  return text === '1' || text === 'true' || text === 'yes' || text === 'on';
}

function asPositiveInt(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.floor(n);
}

function maskSecret(secret) {
  const value = String(secret || '').trim();
  if (!value) return '';
  if (value.length <= 6) return '*'.repeat(value.length);
  return `${value.slice(0, 3)}${'*'.repeat(value.length - 6)}${value.slice(-3)}`;
}

async function ensureRow() {
  await pool.query(
    `INSERT INTO evolution_config (
      id, enabled, base_url, instance_name, api_key, from_number,
      otp_ttl_minutes, send_timeout_ms, template_text, created_at, updated_at
    )
    VALUES ($1, false, NULL, NULL, NULL, NULL, 10, 12000, $2, now(), now())
    ON CONFLICT (id) DO NOTHING`,
    [SINGLETON_ID, DEFAULT_TEMPLATE]
  );
}

function envDefaults() {
  const envBaseUrl =
    process.env.EVOLUTION_API_URL ||
    process.env.EVOLUTION_API_BASE_URL ||
    '';

  const envInstanceName =
    process.env.EVOLUTION_API_INSTANCE_NAME ||
    process.env.EVOLUTION_INSTANCE_NAME ||
    '';

  const envFromNumber =
    process.env.EVOLUTION_OWNER_NUMBER ||
    process.env.EVOLUTION_FROM_NUMBER ||
    '';

  const hasCore =
    String(envBaseUrl || '').trim() &&
    String(envInstanceName || '').trim() &&
    String(process.env.EVOLUTION_API_KEY || '').trim();

  return {
    enabled: asBool(process.env.EVOLUTION_ENABLED, Boolean(hasCore)),
    base_url: normalizeUrl(envBaseUrl),
    instance_name: String(envInstanceName).trim(),
    api_key: String(process.env.EVOLUTION_API_KEY || '').trim(),
    from_number: String(envFromNumber).replace(/[^0-9]/g, ''),
    otp_ttl_minutes: asPositiveInt(process.env.EVOLUTION_OTP_TTL_MINUTES, 10),
    send_timeout_ms: asPositiveInt(process.env.EVOLUTION_SEND_TIMEOUT_MS, 12000),
    template_text: String(process.env.EVOLUTION_TEMPLATE_TEXT || '').trim() || DEFAULT_TEMPLATE
  };
}

function mergedConfig(dbRow) {
  const env = envDefaults();
  const row = dbRow || {};

  const dbHasCore =
    String(row.base_url || '').trim() &&
    String(row.instance_name || '').trim() &&
    String(row.api_key || '').trim();

  const enabled = dbHasCore
    ? Boolean(row.enabled)
    : Boolean(row.enabled || env.enabled);

  return {
    enabled,
    base_url: normalizeUrl(row.base_url || env.base_url),
    instance_name: String(row.instance_name || env.instance_name || '').trim(),
    api_key: String(row.api_key || env.api_key || '').trim(),
    from_number: String(row.from_number || env.from_number || '').replace(/[^0-9]/g, ''),
    otp_ttl_minutes: asPositiveInt(row.otp_ttl_minutes, env.otp_ttl_minutes),
    send_timeout_ms: asPositiveInt(row.send_timeout_ms, env.send_timeout_ms),
    template_text: String(row.template_text || env.template_text || DEFAULT_TEMPLATE).trim() || DEFAULT_TEMPLATE
  };
}

async function getEvolutionConfig() {
  try {
    await ensureRow();
    const res = await pool.query(
      `SELECT id, enabled, base_url, instance_name, api_key, from_number,
              otp_ttl_minutes, send_timeout_ms, template_text, created_at, updated_at
       FROM evolution_config
       WHERE id = $1
       LIMIT 1`,
      [SINGLETON_ID]
    );

    return mergedConfig(res.rows[0] || null);
  } catch (error) {
    console.error('getEvolutionConfig error:', error);
    return mergedConfig(null);
  }
}

async function getEvolutionConfigForAdmin() {
  const config = await getEvolutionConfig();
  return {
    ...config,
    api_key_masked: maskSecret(config.api_key),
    has_api_key: Boolean(config.api_key),
    api_key: ''
  };
}

async function updateEvolutionConfig(payload) {
  await ensureRow();

  const current = await getEvolutionConfig();
  const next = {
    enabled: payload.enabled === undefined ? current.enabled : asBool(payload.enabled, current.enabled),
    base_url: payload.base_url === undefined ? current.base_url : normalizeUrl(payload.base_url),
    instance_name:
      payload.instance_name === undefined
        ? current.instance_name
        : String(payload.instance_name || '').trim(),
    api_key:
      payload.api_key === undefined
        ? current.api_key
        : String(payload.api_key || '').trim(),
    from_number:
      payload.from_number === undefined
        ? current.from_number
        : String(payload.from_number || '').replace(/[^0-9]/g, ''),
    otp_ttl_minutes:
      payload.otp_ttl_minutes === undefined
        ? current.otp_ttl_minutes
        : asPositiveInt(payload.otp_ttl_minutes, current.otp_ttl_minutes),
    send_timeout_ms:
      payload.send_timeout_ms === undefined
        ? current.send_timeout_ms
        : asPositiveInt(payload.send_timeout_ms, current.send_timeout_ms),
    template_text:
      payload.template_text === undefined
        ? current.template_text
        : String(payload.template_text || '').trim() || DEFAULT_TEMPLATE
  };

  if (next.enabled) {
    if (!next.base_url) throw new Error('base_url es requerido cuando Evolution está habilitado');
    if (!next.instance_name) throw new Error('instance_name es requerido cuando Evolution está habilitado');
    if (!next.api_key) throw new Error('api_key es requerido cuando Evolution está habilitado');
  }

  const res = await pool.query(
    `UPDATE evolution_config
     SET enabled = $2,
         base_url = $3,
         instance_name = $4,
         api_key = $5,
         from_number = $6,
         otp_ttl_minutes = $7,
         send_timeout_ms = $8,
         template_text = $9,
         updated_at = now()
     WHERE id = $1
     RETURNING id`,
    [
      SINGLETON_ID,
      next.enabled,
      asNullableTrimmed(next.base_url),
      asNullableTrimmed(next.instance_name),
      asNullableTrimmed(next.api_key),
      asNullableTrimmed(next.from_number),
      next.otp_ttl_minutes,
      next.send_timeout_ms,
      next.template_text
    ]
  );

  if (!res.rows || res.rows.length === 0) {
    throw new Error('No se pudo actualizar evolution_config');
  }

  return getEvolutionConfigForAdmin();
}

module.exports = {
  getEvolutionConfig,
  getEvolutionConfigForAdmin,
  updateEvolutionConfig,
  maskSecret
};
