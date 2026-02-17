const { pool } = require('../db/pool');

const SUPPORT_CONFIG_ID = '00000000-0000-0000-0000-000000000002';

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
  return {
    id: SUPPORT_CONFIG_ID,
    base_url: normalizeText(process.env.EVOLUTION_BASE_URL),
    instance_name: normalizeText(process.env.EVOLUTION_INSTANCE_NAME),
    api_key: normalizeText(process.env.EVOLUTION_API_KEY),
  };
}

async function ensureSupportMessageConfigTable() {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS support_message_config (
      id uuid PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000002'::uuid,
      base_url text,
      instance_name text,
      api_key text,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    )`
  );
}

async function getStoredConfig() {
  await ensureSupportMessageConfigTable();
  const res = await pool.query(
    `SELECT id, base_url, instance_name, api_key, created_at, updated_at
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

  const baseUrl = normalizeText(next.base_url);
  const instanceName = normalizeText(next.instance_name);
  const apiKey = normalizeText(next.api_key);

  if (!baseUrl || !instanceName || !apiKey) {
    throw new Error('Configuración incompleta: base_url, instance_name y api_key son requeridos');
  }

  await ensureSupportMessageConfigTable();

  const hasEnabledCol = await pool.query(
    `SELECT 1
     FROM information_schema.columns
     WHERE table_name = 'support_message_config' AND column_name = 'enabled'
     LIMIT 1`
  );

  if (hasEnabledCol.rows.length > 0) {
    await pool.query(
      `ALTER TABLE support_message_config
       ALTER COLUMN enabled SET DEFAULT true`
    );
  }

  const res = await pool.query(
    `INSERT INTO support_message_config (
      id, base_url, instance_name, api_key, created_at, updated_at
    ) VALUES ($1,$2,$3,$4, now(), now())
    ON CONFLICT (id) DO UPDATE SET
      base_url = EXCLUDED.base_url,
      instance_name = EXCLUDED.instance_name,
      api_key = EXCLUDED.api_key,
      updated_at = now()
    RETURNING id, base_url, instance_name, api_key, created_at, updated_at`,
    [
      SUPPORT_CONFIG_ID,
      baseUrl || null,
      instanceName || null,
      apiKey || null
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
    base_url: normalizeText(stored.base_url) || defaults.base_url,
    instance_name: normalizeText(stored.instance_name) || defaults.instance_name,
    api_key: normalizeText(stored.api_key) || defaults.api_key,
    created_at: stored.created_at,
    updated_at: stored.updated_at
  };
}

async function getSupportMessageConfigForAdmin() {
  const cfg = await getRuntimeConfig();
  return {
    base_url: cfg.base_url,
    instance_name: cfg.instance_name,
    api_key_masked: maskApiKey(cfg.api_key),
    updated_at: cfg.updated_at || null
  };
}

async function updateSupportMessageConfig(payload) {
  const partial = {
    base_url: payload.base_url,
    instance_name: payload.instance_name,
  };

  if (Object.prototype.hasOwnProperty.call(payload, 'api_key')) {
    partial.api_key = payload.api_key;
  }

  const stored = await upsertConfig(partial);
  return {
    base_url: normalizeText(stored.base_url),
    instance_name: normalizeText(stored.instance_name),
    api_key_masked: maskApiKey(stored.api_key),
    updated_at: stored.updated_at || null
  };
}

module.exports = {
  getRuntimeConfig,
  getSupportMessageConfigForAdmin,
  updateSupportMessageConfig,
  normalizePhone
};
