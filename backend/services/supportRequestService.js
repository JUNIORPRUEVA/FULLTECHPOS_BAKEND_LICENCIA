const { pool } = require('../db/pool');
const supportMessageConfigService = require('./supportMessageConfigService');

const SUPPORT_DEST_PHONE = supportMessageConfigService.normalizePhone(
  process.env.SUPPORT_WHATSAPP_PHONE || process.env.WHATSAPP_SUPPORT_PHONE || '18295319442'
);

function normalizeText(value) {
  return String(value || '').trim();
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

async function findActiveLicenseByBusinessId(businessId) {
  const res = await pool.query(
    `SELECT l.license_key, l.license_type, l.estado, l.fecha_inicio, l.fecha_fin, l.max_dispositivos
     FROM licenses l
     WHERE l.business_id = $1
     ORDER BY (l.estado = 'ACTIVA') DESC, l.fecha_fin DESC NULLS LAST, l.created_at DESC
     LIMIT 1`,
    [businessId]
  );
  return res.rows[0] || null;
}

function formatDate(value) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toISOString().slice(0, 10);
}

function buildSupportMessage(fields) {
  return [
    'SOLICITUD DE SOPORTE FULLPOS',
    `Business ID: ${fields.businessId}`,
    `Negocio: ${fields.businessName}`,
    `Propietario: ${fields.ownerName}`,
    `Teléfono: ${fields.phone}`,
    `Email: ${fields.email}`,
    `Usuario local: ${fields.username}`,
    `Licencia activa: ${fields.licenseKey}`,
    `Tipo licencia: ${fields.licenseType}`,
    `Estado licencia: ${fields.licenseStatus}`,
    `Vigencia: ${fields.licenseStart} -> ${fields.licenseEnd}`,
    `Máx dispositivos: ${fields.licenseMaxDevices}`,
    `Detalle: ${fields.clientMessage}`,
    `Fecha: ${fields.timestamp}`
  ].join('\n');
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

  if (!cfg.base_url || !cfg.instance_name || !cfg.api_key) {
    const err = new Error('Configuración de Evolution incompleta en admin');
    err.status = 503;
    throw err;
  }

  if (!SUPPORT_DEST_PHONE) {
    const err = new Error('No hay número de soporte configurado en el servidor');
    err.status = 503;
    throw err;
  }

  const customer = await findCustomerByBusinessId(normalizedBusinessId);
  const license = await findActiveLicenseByBusinessId(normalizedBusinessId);

  const effectiveBusinessName = normalizeText(customer?.nombre_negocio) || normalizeText(businessName) || '-';
  const effectiveOwnerName = normalizeText(customer?.contacto_nombre) || normalizeText(ownerName) || '-';
  const effectivePhone = supportMessageConfigService.normalizePhone(customer?.contacto_telefono) || supportMessageConfigService.normalizePhone(phone) || '-';
  const effectiveEmail = normalizeText(customer?.contacto_email) || normalizeText(email) || '-';
  const effectiveUsername = normalizeText(username) || 'admin';
  const effectiveMessage = normalizeText(message) || 'Cliente solicita soporte para recuperación de contraseña.';
  const ts = new Date().toISOString();

  const text = buildSupportMessage({
    businessId: normalizedBusinessId,
    businessName: effectiveBusinessName,
    ownerName: effectiveOwnerName,
    phone: effectivePhone,
    email: effectiveEmail,
    username: effectiveUsername,
    licenseKey: normalizeText(license?.license_key) || '-',
    licenseType: normalizeText(license?.license_type) || '-',
    licenseStatus: normalizeText(license?.estado) || '-',
    licenseStart: formatDate(license?.fecha_inicio),
    licenseEnd: formatDate(license?.fecha_fin),
    licenseMaxDevices: String(license?.max_dispositivos ?? '-'),
    clientMessage: effectiveMessage,
    timestamp: ts
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
      number: SUPPORT_DEST_PHONE,
      text
    }),
    signal: AbortSignal.timeout(Math.max(3000, Number(process.env.EVOLUTION_SEND_TIMEOUT_MS || 12000) || 12000))
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
