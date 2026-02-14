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
  return fs.readFileSync(fullPath, 'utf8');
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

function buildPayload({
  project_code,
  business_id,
  license_key,
  tipo,
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
    business_id: business_id ? String(business_id).trim() : null,
    license_key: String(license_key || '').trim(),
    tipo: String(tipo || '').toUpperCase(),
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

function signLicensePayload(payload, privateKeyPem) {
  const payloadJson = JSON.stringify(payload);
  const signature = crypto.sign(null, Buffer.from(payloadJson, 'utf8'), privateKeyPem);
  return {
    payload,
    signature: signature.toString('base64'),
    alg: 'Ed25519'
  };
}

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

function createLicenseFileFromDbRows({ license, project, customer, device_id }) {
  if (!license) throw new Error('license requerido');
  if (!project) throw new Error('project requerido');

  if (!license.fecha_inicio || !license.fecha_fin) {
    const err = new Error('La licencia debe tener fecha_inicio y fecha_fin para exportar archivo offline');
    err.code = 'LICENSE_NOT_STARTED';
    throw err;
  }

  const privateKeyPem = getPrivateKeyPem();

  const payload = buildPayload({
    project_code: project.code,
    business_id: (customer && customer.business_id) ? customer.business_id : license.business_id,
    license_key: license.license_key,
    tipo: license.tipo,
    fecha_inicio: license.fecha_inicio,
    fecha_fin: license.fecha_fin,
    dias_validez: license.dias_validez,
    max_dispositivos: license.max_dispositivos,
    device_id,
    customer
  });

  return signLicensePayload(payload, privateKeyPem);
}

module.exports = {
  buildPayload,
  signLicensePayload,
  verifyLicenseFile,
  createLicenseFileFromDbRows,
  getPublicKeyPem,
  getPrivateKeyPem
};
