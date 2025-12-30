const crypto = require('crypto');

function randomSegment(length) {
  // Base32-ish (sin caracteres confusos)
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i++) {
    out += alphabet[bytes[i] % alphabet.length];
  }
  return out;
}

function generateLicenseKey(tipo) {
  const upperTipo = String(tipo || '').toUpperCase();
  const prefix = upperTipo === 'FULL' ? 'FULL' : 'DEMO';
  return `${prefix}-${randomSegment(5)}-${randomSegment(5)}-${randomSegment(5)}`;
}

module.exports = { generateLicenseKey };
