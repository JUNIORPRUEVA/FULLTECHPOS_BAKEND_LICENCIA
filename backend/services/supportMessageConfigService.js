const { pool } = require('../db/pool');

const SUPPORT_CONFIG_ID = '00000000-0000-0000-0000-000000000002';

function normalizeBool(value) {
  if (typeof value === 'boolean') return value;
  const str = String(value || '').trim().toLowerCase();
  return str === '1' || str === 'true' || str === 'yes' || str === 'on';
}

function normalizeText(value) {
  return String(value || '').trim();
}

function normalizePhone(value) {
  return String(value || '').replace(/[^0-9]/g, '');
}

function maskApiKey(key) {
  const raw = String(key || '').trim();
  if (!raw) return '(sin API key guardada)';
  if (raw.length <= 8) return `${raw.slice(0, 2)}***${raw.slice(-1)}`;
  return `${raw.slice(0, 4)}***${raw.slice(-4)}`;
}

function envDefaults() {
  const enabledRaw = process.env.EVOLUTION_ENABLED || process.env.SUPPORT_MSG_ENABLED || 'false';
  const enabled = normalizeBool(enabledRaw);

  return {
    id: SUPPORT_CONFIG_ID,
    enabled,
    base_url: normalizeText(process.env.EVOLUTION_BASE_URL),
    instance_name: normalizeText(process.env.EVOLUTION_INSTANCE_NAME),
    api_key: normalizeText(process.env.EVOLUTION_API_KEY),
    support_phone: normalizePhone(process.env.SUPPORT_WHATSAPP_PHONE || process.env.WHATSAPP_SUPPORT_PHONE),
    send_timeout_ms: Math.max(3000, Number(process.env.EVOLUTION_SEND_TIMEOUT_MS || 12000) || 12000),
    template_text: normalizeText(process.env.SUPPORT_MSG_TEMPLATE) ||
      'Solicitud de soporte FULLPOS\nBusiness ID: {business_id}\nNegocio: {business_name}\nPropietario: {owner_name}\nTeléfono: {phone}\nEmail: {email}\nUsuario: {username}\nDetalle: {client_message}\nFecha: {ts}'
  };
}

async function getStoredConfig() {
  const res = await pool.query(
    `SELECT id, enabled, base_url, instance_name, api_key, support_phone, send_timeout_ms, template_text, created_at, updated_at
     FROM support_message_config
     WHERE id = $1
     LIMIT 1`,
    [SUPPORT_CONFIG_ID]
  );
  return res.rows[0] || null;
}

async function upsertConfig(partial) {
  const current = await getRuntimeConfig();
  const next = {
    ...current,
    ...partial
  };

  const enabled = normalizeBool(next.enabled);
  const baseUrl = normalizeText(next.base_url);
  const instanceName = normalizeText(next.instance_name);
  const apiKey = normalizeText(next.api_key);
  const supportPhone = normalizePhone(next.support_phone);
  const sendTimeoutMs = Math.max(3000, Number(next.send_timeout_ms || 12000) || 12000);
  const templateText = normalizeText(next.template_text) || current.template_text;

  if (enabled) {
    if (!baseUrl || !instanceName || !apiKey || !supportPhone) {
      throw new Error('Configuración incompleta: base_url, instance_name, api_key y support_phone son requeridos cuando está habilitado');
    }
  }

  const res = await pool.query(
    `INSERT INTO support_message_config (
      id, enabled, base_url, instance_name, api_key, support_phone,
      send_timeout_ms, template_text, created_at, updated_at
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8, now(), now())
    ON CONFLICT (id) DO UPDATE SET
      enabled = EXCLUDED.enabled,
      base_url = EXCLUDED.base_url,
      instance_name = EXCLUDED.instance_name,
      api_key = EXCLUDED.api_key,
      support_phone = EXCLUDED.support_phone,
      send_timeout_ms = EXCLUDED.send_timeout_ms,
      template_text = EXCLUDED.template_text,
      updated_at = now()
    RETURNING id, enabled, base_url, instance_name, api_key, support_phone, send_timeout_ms, template_text, created_at, updated_at`,
    [
      SUPPORT_CONFIG_ID,
      enabled,
      baseUrl || null,
      instanceName || null,
      apiKey || null,
      supportPhone || null,
      sendTimeoutMs,
      templateText
    ]
  );

  return res.rows[0] || null;
}

async function getRuntimeConfig() {
  const defaults = envDefaults();
  const stored = await getStoredConfig();
  if (!stored) return defaults;

  return {
    id: stored.id,
    enabled: normalizeBool(stored.enabled),
    base_url: normalizeText(stored.base_url) || defaults.base_url,
    instance_name: normalizeText(stored.instance_name) || defaults.instance_name,
    api_key: normalizeText(stored.api_key) || defaults.api_key,
    support_phone: normalizePhone(stored.support_phone) || defaults.support_phone,
    send_timeout_ms: Math.max(3000, Number(stored.send_timeout_ms || defaults.send_timeout_ms) || defaults.send_timeout_ms),
    template_text: normalizeText(stored.template_text) || defaults.template_text,
    created_at: stored.created_at,
    updated_at: stored.updated_at
  };
}

async function getSupportMessageConfigForAdmin() {
  const cfg = await getRuntimeConfig();
  return {
    enabled: cfg.enabled,
    base_url: cfg.base_url,
    instance_name: cfg.instance_name,
    api_key_masked: maskApiKey(cfg.api_key),
    support_phone: cfg.support_phone,
    send_timeout_ms: cfg.send_timeout_ms,
    template_text: cfg.template_text,
    updated_at: cfg.updated_at || null
  };
}

async function updateSupportMessageConfig(payload) {
  const partial = {
    enabled: payload.enabled,
    base_url: payload.base_url,
    instance_name: payload.instance_name,
    support_phone: payload.support_phone,
    send_timeout_ms: payload.send_timeout_ms,
    template_text: payload.template_text
  };

  if (Object.prototype.hasOwnProperty.call(payload, 'api_key')) {
    partial.api_key = payload.api_key;
  }

  const stored = await upsertConfig(partial);
  return {
    enabled: normalizeBool(stored.enabled),
    base_url: normalizeText(stored.base_url),
    instance_name: normalizeText(stored.instance_name),
    api_key_masked: maskApiKey(stored.api_key),
    support_phone: normalizePhone(stored.support_phone),
    send_timeout_ms: Math.max(3000, Number(stored.send_timeout_ms || 12000) || 12000),
    template_text: normalizeText(stored.template_text),
    updated_at: stored.updated_at || null
  };
}

module.exports = {
  getRuntimeConfig,
  getSupportMessageConfigForAdmin,
  updateSupportMessageConfig,
  normalizePhone
};
