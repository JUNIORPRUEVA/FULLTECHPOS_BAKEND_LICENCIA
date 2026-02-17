const { pool } = require('../db/pool');
const supportMessageConfigService = require('./supportMessageConfigService');

function normalizeText(value) {
  return String(value || '').trim();
}

function fillTemplate(template, fields) {
  let text = String(template || '');
  Object.entries(fields).forEach(([key, value]) => {
    const safe = String(value == null ? '' : value);
    text = text.split(`{${key}}`).join(safe);
  });
  return text;
}

async function findCustomerByBusinessId(businessId) {
  const res = await pool.query(
    `SELECT business_id, nombre_negocio, contacto_nombre, contacto_telefono, contacto_email
     FROM customers
     WHERE business_id = $1
     LIMIT 1`,
    [businessId]
  );
  return res.rows[0] || null;
}

async function sendSupportMessage({
  businessId,
  username,
  businessName,
  ownerName,
  phone,
  email,
  message
}) {
  const normalizedBusinessId = normalizeText(businessId);
  if (!normalizedBusinessId) {
    const err = new Error('business_id es requerido');
    err.status = 400;
    throw err;
  }

  const cfg = await supportMessageConfigService.getRuntimeConfig();
  if (!cfg.enabled) {
    const err = new Error('Soporte por mensajería está deshabilitado');
    err.status = 503;
    throw err;
  }

  if (!cfg.base_url || !cfg.instance_name || !cfg.api_key || !cfg.support_phone) {
    const err = new Error('Configuración de Evolution incompleta en admin');
    err.status = 503;
    throw err;
  }

  const customer = await findCustomerByBusinessId(normalizedBusinessId);

  const effectiveBusinessName = normalizeText(customer?.nombre_negocio) || normalizeText(businessName) || '-';
  const effectiveOwnerName = normalizeText(customer?.contacto_nombre) || normalizeText(ownerName) || '-';
  const effectivePhone = supportMessageConfigService.normalizePhone(customer?.contacto_telefono) || supportMessageConfigService.normalizePhone(phone) || '-';
  const effectiveEmail = normalizeText(customer?.contacto_email) || normalizeText(email) || '-';
  const effectiveUsername = normalizeText(username) || 'admin';
  const effectiveMessage = normalizeText(message) || 'Cliente solicita soporte para recuperación de contraseña.';
  const ts = new Date().toISOString();

  const text = fillTemplate(cfg.template_text, {
    business_id: normalizedBusinessId,
    business_name: effectiveBusinessName,
    owner_name: effectiveOwnerName,
    phone: effectivePhone,
    email: effectiveEmail,
    username: effectiveUsername,
    client_message: effectiveMessage,
    ts
  });

  const base = String(cfg.base_url).replace(/\/+$/, '');
  const endpoint = `${base}/message/sendText/${encodeURIComponent(cfg.instance_name)}`;

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: cfg.api_key
    },
    body: JSON.stringify({
      number: cfg.support_phone,
      text
    }),
    signal: AbortSignal.timeout(Math.max(3000, Number(cfg.send_timeout_ms || 12000)))
  });

  const raw = await response.text();
  let parsed;
  try {
    parsed = raw ? JSON.parse(raw) : null;
  } catch (_) {
    parsed = null;
  }

  if (!response.ok) {
    const detail = parsed && (parsed.message || parsed.error)
      ? String(parsed.message || parsed.error)
      : raw.slice(0, 240);
    const err = new Error(`Evolution API HTTP ${response.status}${detail ? `: ${detail}` : ''}`);
    err.status = 502;
    throw err;
  }

  return {
    ok: true,
    provider_status: parsed && parsed.status ? parsed.status : 'accepted'
  };
}

module.exports = {
  sendSupportMessage
};
