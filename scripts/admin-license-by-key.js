/* eslint-disable no-console */

// Admin helper:
// Block/expire/activate a license by license_key (works for offline-uploaded licenses too).
//
// Usage examples:
//   node scripts/admin-license-by-key.js block LICENSE-KEY-HERE
//   node scripts/admin-license-by-key.js expire LICENSE-KEY-HERE
//   node scripts/admin-license-by-key.js activate LICENSE-KEY-HERE
//
// Env:
//   BASE_URL (default http://127.0.0.1:3000)
//   ADMIN_USERNAME / ADMIN_PASSWORD

async function main() {
  const base = process.env.BASE_URL || 'http://127.0.0.1:3000';
  const username = process.env.ADMIN_USERNAME || 'fulltechsd@gmail.com';
  const password = process.env.ADMIN_PASSWORD || 'Ayleen10';

  const [cmd, licenseKey] = process.argv.slice(2);

  const command = String(cmd || '').trim().toLowerCase();
  const key = String(licenseKey || '').trim();

  if (!['block', 'expire', 'activate'].includes(command) || !key) {
    console.log('Usage: node scripts/admin-license-by-key.js block|expire|activate <LICENSE_KEY>');
    process.exitCode = 1;
    return;
  }

  const loginRes = await fetch(`${base}/api/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, password })
  });
  const loginData = await loginRes.json();
  if (!loginRes.ok || !loginData.sessionId) {
    throw new Error(`Login failed (${loginRes.status}): ${JSON.stringify(loginData)}`);
  }

  const sessionId = loginData.sessionId;

  let path = '';
  if (command === 'block') path = '/api/admin/licenses/by-key/bloquear';
  if (command === 'expire') path = '/api/admin/licenses/by-key/vencer';
  if (command === 'activate') path = '/api/admin/licenses/by-key/activar-manual';

  const res = await fetch(`${base}${path}`, {
    method: 'PATCH',
    headers: {
      'content-type': 'application/json',
      'x-session-id': sessionId
    },
    body: JSON.stringify({ license_key: key })
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.ok !== true) {
    throw new Error(`Request failed (${res.status}): ${JSON.stringify(data)}`);
  }

  console.log(JSON.stringify({ ok: true, action: command, license: data.license }, null, 2));
}

main().catch(err => {
  console.error('FAILED:', err?.message || err);
  process.exit(1);
});
