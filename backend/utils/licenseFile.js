const crypto = require('crypto');

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !String(value).trim()) {
    const err = new Error(`Missing env: ${name}`);
    err.code = 'MISSING_ENV';
    throw err;
  }
  return String(value);
}

function buildPayload({
  project_code,
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

  const privateKeyPem = requireEnv('LICENSE_SIGN_PRIVATE_KEY');

  const payload = buildPayload({
    project_code: project.code,
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

function getPublicKeyPem() {
  return requireEnv('LICENSE_SIGN_PUBLIC_KEY');
}

module.exports = {
  buildPayload,
  signLicensePayload,
  verifyLicenseFile,
  createLicenseFileFromDbRows,
  getPublicKeyPem
};
