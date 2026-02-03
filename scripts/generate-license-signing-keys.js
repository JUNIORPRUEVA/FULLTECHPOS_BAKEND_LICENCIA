const crypto = require('crypto');

// Generates Ed25519 keypair for offline license signing.
// Usage: node scripts/generate-license-signing-keys.js

const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');

const publicPem = publicKey.export({ type: 'spki', format: 'pem' });
const privatePem = privateKey.export({ type: 'pkcs8', format: 'pem' });

console.log('LICENSE_SIGN_PUBLIC_KEY=');
console.log(publicPem.trim());
console.log('\nLICENSE_SIGN_PRIVATE_KEY=');
console.log(privatePem.trim());
