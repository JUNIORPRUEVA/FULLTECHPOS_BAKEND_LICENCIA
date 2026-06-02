const crypto = require('crypto');
const fs = require('fs');

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !String(value).trim()) {
    const err = new Error(`Missing env: ${name}`);
    err.code = 'MISSING_ENV';
    throw err;
  }
  return String(value);
}

function normalizePem(value) {
  if (!value) return '';
  const raw = String(value).trim();
  // dotenv suele dejar \n literal en env vars; crypto espera saltos reales.
  return raw.replace(/\\n/g, '\n');
}

function readPemFromFileEnv(fileEnvName) {
  const filePath = process.env[fileEnvName];
  if (!filePath || !String(filePath).trim()) return null;
  const fullPath = String(filePath).trim();
  try {
    return fs.readFileSync(fullPath, 'utf8');
  } catch (e) {
    console.error(`[licenseFile] No se pudo leer archivo PEM: ${fullPath}`, e.message);
    return null;
  }
}

function getPrivateKeyPem() {
  // Preferimos *_FILE para evitar problemas con PEM multiline.
  const fromFile = readPemFromFileEnv('LICENSE_SIGN_PRIVATE_KEY_FILE');
  if (fromFile && String(fromFile).trim()) return normalizePem(fromFile);
  return normalizePem(requireEnv('LICENSE_SIGN_PRIVATE_KEY'));
}

function getPublicKeyPem() {
  const fromFile = readPemFromFileEnv('LICENSE_SIGN_PUBLIC_KEY_FILE');
  if (fromFile && String(fromFile).trim()) return normalizePem(fromFile);
  return normalizePem(requireEnv('LICENSE_SIGN_PUBLIC_KEY'));
}

/**
 * Construye el payload interno de la licencia (sin firma).
 * Este payload es lo que se firma con Ed25519.
 */
function buildPayload({
  project_code,
  project_name,
  business_id,
  license_key,
  tipo,
  license_type,
  fecha_inicio,
  fecha_fin,
  dias_validez,
  max_dispositivos,
  device_id,
  customer
}) {
  // IMPORTANT: keep insertion order stable (used for signing)
  return {
    v: 1,
    project_code: String(project_code || '').toUpperCase(),
    project_name: project_name ? String(project_name).trim() : null,
    business_id: business_id ? String(business_id).trim() : null,
    license_key: String(license_key || '').trim(),
    tipo: String(tipo || '').toUpperCase(),
    license_type: String(license_type || 'SUSCRIPCION').toUpperCase(),
    fecha_inicio: fecha_inicio ? new Date(fecha_inicio).toISOString() : null,
    fecha_fin: fecha_fin ? new Date(fecha_fin).toISOString() : null,
    dias_validez: Number(dias_validez),
    max_dispositivos: Number(max_dispositivos),
    device_id: device_id ? String(device_id).trim() : null,
    customer: customer
      ? {
          id: customer.id || null,
          nombre_negocio: customer.nombre_negocio || null
        }
      : null,
    issued_at: new Date().toISOString()
  };
}

/**
 * Firma el payload con la clave privada Ed25519.
 * Retorna { payload, signature, alg }
 */
function signLicensePayload(payload, privateKeyPem) {
  const payloadJson = JSON.stringify(payload);
  const signature = crypto.sign(null, Buffer.from(payloadJson, 'utf8'), privateKeyPem);
  return {
    payload,
    signature: signature.toString('base64'),
    alg: 'Ed25519'
  };
}

/**
 * Verifica la firma de un archivo de licencia.
 * Retorna { ok: boolean, reason: string }
 */
function verifyLicenseFile(licenseFile, publicKeyPem) {
  if (!licenseFile || typeof licenseFile !== 'object') {
    return { ok: false, reason: 'INVALID_FORMAT' };
  }
  if (!licenseFile.payload || !licenseFile.signature) {
    return { ok: false, reason: 'MISSING_FIELDS' };
  }
  const payloadJson = JSON.stringify(licenseFile.payload);
  const signatureBuf = Buffer.from(String(licenseFile.signature), 'base64');
  const ok = crypto.verify(null, Buffer.from(payloadJson, 'utf8'), publicKeyPem, signatureBuf);
  return { ok, reason: ok ? 'OK' : 'BAD_SIGNATURE' };
}

/**
 * Crea el archivo de licencia completo con envoltorio profesional (.fulllicense).
 * 
 * Estructura:
 * {
 *   "schema_version": 1,
 *   "file_type": "APPYRA_LICENSE_FILE",
 *   "generated_at": "...",
 *   "license": { ... datos de la licencia ... },
 *   "constraints": { ... restricciones ... },
 *   "signature": "..."
 * }
 */
function createLicenseFileFromDbRows({ license, project, customer, device_id }) {
  if (!license) throw new Error('license requerido');
  if (!project) throw new Error('project requerido');

  if (!license.fecha_inicio || !license.fecha_fin) {
    const err = new Error('La licencia debe tener fecha_inicio y fecha_fin para exportar archivo offline');
    err.code = 'LICENSE_NOT_STARTED';
    throw err;
  }

  const privateKeyPem = getPrivateKeyPem();

  // Construir payload interno (lo que se firma)
  const payload = buildPayload({
    project_code: project.code,
    project_name: project.name,
    business_id: (customer && customer.business_id) ? customer.business_id : license.business_id,
    license_key: license.license_key,
    tipo: license.tipo,
    license_type: license.license_type || 'SUSCRIPCION',
    fecha_inicio: license.fecha_inicio,
    fecha_fin: license.fecha_fin,
    dias_validez: license.dias_validez,
    max_dispositivos: license.max_dispositivos,
    device_id,
    customer
  });

  // Firmar el payload
  const signed = signLicensePayload(payload, privateKeyPem);

  // Envoltorio profesional del archivo
  // NOTA: El payload contiene los datos firmados. El importador espera
  // la estructura { file_type, payload, signature }.
  const licenseFile = {
    schema_version: 1,
    file_type: 'APPYRA_LICENSE_FILE',
    generated_at: new Date().toISOString(),
    payload: {
      id: license.id,
      license_key: license.license_key,
      project_id: project.id,
      project_code: String(project.code || '').toUpperCase(),
      project_name: project.name || null,
      customer_id: (customer && customer.id) || license.customer_id || null,
      customer_name: (customer && customer.nombre_negocio) || null,
      type: String(license.tipo || '').toUpperCase(),
      license_type: String(license.license_type || 'SUSCRIPCION').toUpperCase(),
      status: String(license.estado || '').toUpperCase(),
      activation_source: 'file',
      issued_at: license.fecha_inicio ? new Date(license.fecha_inicio).toISOString() : null,
      expires_at: license.fecha_fin ? new Date(license.fecha_fin).toISOString() : null,
      days_valid: Number(license.dias_validez) || 0,
      max_devices: Number(license.max_dispositivos) || 1,
      allow_offline_activation: true,
      allow_device_binding_on_import: true
    },
    constraints: {
      bind_to_device_on_import: true,
      requires_internet_after_import: false,
      max_imports: 1
    },
    signature: signed.signature,
    alg: signed.alg
  };

  return licenseFile;
}

/**
 * Genera el nombre de archivo para descarga.
 * Formato: {PROJECT_CODE}_LIC-{TIPO}-{SHORT_KEY}-{YYYYMMDD}.fulllicense
 */
function buildLicenseFileName({ project_code, license_key, tipo }) {
  const projectCode = String(project_code || 'UNKNOWN').toUpperCase();
  const tipoShort = String(tipo || 'LIC').toUpperCase().substring(0, 3);
  const keyShort = String(license_key || '').replace(/[^A-Z0-9]/gi, '').substring(0, 8).toUpperCase();
  const dateStr = new Date().toISOString().substring(0, 10).replace(/-/g, '');
  return `${projectCode}_${tipoShort}-${keyShort}-${dateStr}.fulllicense`;
}

module.exports = {
  buildPayload,
  signLicensePayload,
  verifyLicenseFile,
  createLicenseFileFromDbRows,
  buildLicenseFileName,
  getPublicKeyPem,
  getPrivateKeyPem
};
