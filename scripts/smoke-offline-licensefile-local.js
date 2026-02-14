/*
  Smoke test (local/offline) for exported offline license file format.

  Goal:
    - Ensure licenseFile.createLicenseFileFromDbRows includes business_id in payload
    - Ensure signature verifies using generated Ed25519 keypair

  Usage:
    node scripts/smoke-offline-licensefile-local.js

  Notes:
    - No DB required.
    - Generates an ephemeral Ed25519 keypair.
*/

const crypto = require('crypto');
const licenseFile = require('../backend/utils/licenseFile');

function generateEd25519PemPair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const publicKeyPem = publicKey.export({ format: 'pem', type: 'spki' });
  const privateKeyPem = privateKey.export({ format: 'pem', type: 'pkcs8' });
  return { publicKeyPem, privateKeyPem };
}

function assert(condition, message) {
  if (!condition) {
    const err = new Error(message);
    err.code = 'ASSERT_FAIL';
    throw err;
  }
}

(async () => {
  const { publicKeyPem, privateKeyPem } = generateEd25519PemPair();

  // Satisfy env requirements used by backend/utils/licenseFile.js
  process.env.LICENSE_SIGN_PRIVATE_KEY = privateKeyPem;
  process.env.LICENSE_SIGN_PUBLIC_KEY = publicKeyPem;

  const dummy = {
    license: {
      license_key: 'LIC-TEST-001',
      tipo: 'FULL',
      fecha_inicio: new Date(Date.now() - 60_000).toISOString(),
      fecha_fin: new Date(Date.now() + 24 * 60 * 60_000).toISOString(),
      dias_validez: 30,
      max_dispositivos: 1,
      // Important: comes from licensesModel.getLicenseById join
      business_id: 'biz_test_123'
    },
    project: {
      code: 'FULLPOS'
    },
    customer: {
      id: 10,
      nombre_negocio: 'NEGOCIO TEST',
      business_id: 'biz_test_123'
    },
    device_id: null
  };

  const fileObj = licenseFile.createLicenseFileFromDbRows(dummy);

  assert(fileObj && typeof fileObj === 'object', 'Expected file object');
  assert(fileObj.alg === 'Ed25519', 'Expected alg Ed25519');
  assert(fileObj.payload && typeof fileObj.payload === 'object', 'Expected payload object');

  const payload = fileObj.payload;
  assert(payload.project_code === 'FULLPOS', 'Expected project_code FULLPOS');
  assert(payload.license_key === 'LIC-TEST-001', 'Expected license_key');
  assert(payload.business_id === 'biz_test_123', 'Expected business_id in payload');

  const vr = licenseFile.verifyLicenseFile(fileObj, publicKeyPem);
  assert(vr && vr.ok === true, 'Expected signature verify ok');

  console.log('OK: offline license file includes business_id and signature verifies');
  console.log(JSON.stringify({ payload: fileObj.payload, alg: fileObj.alg }, null, 2));
})().catch((e) => {
  console.error('FAIL:', e && e.message ? e.message : e);
  process.exitCode = 1;
});
