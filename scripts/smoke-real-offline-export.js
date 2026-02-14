/*
  Smoke test against real backend (api.fulltechrd.com)

  What it does:
    1) Uses admin session (x-session-id) to list licenses (first page)
    2) Picks a license id (or accepts --license)
    3) Calls /api/admin/licenses/:id/license-file?ensure_active=true to get JSON
    4) Validates payload.business_id is present
    5) Calls public /businesses/:business_id/license to see cloud status (200/204)

  Usage:
    node scripts/smoke-real-offline-export.js --session <X_SESSION_ID>

  Optional:
    API_ORIGIN=https://api.fulltechrd.com node scripts/smoke-real-offline-export.js --session <X_SESSION_ID>
    node scripts/smoke-real-offline-export.js --session <X_SESSION_ID> --license <LICENSE_ID>
*/

const https = require('https');

const API_ORIGIN = (process.env.API_ORIGIN || 'https://api.fulltechrd.com').replace(/\/$/, '');

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--session') out.session = args[++i];
    if (a === '--license') out.license = args[++i];
  }
  return out;
}

function requestJson(path, { method = 'GET', headers = {}, body = null } = {}) {
  return new Promise((resolve) => {
    const url = API_ORIGIN + path;
    const req = https.request(
      url,
      {
        method,
        headers: {
          'accept': 'application/json',
          ...headers
        }
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => {
          let json = null;
          try {
            json = JSON.parse(raw);
          } catch {
            json = null;
          }
          resolve({ url, status: res.statusCode, json, raw: raw.slice(0, 3000) });
        });
      }
    );

    req.on('error', (e) => resolve({ url, status: 'ERR', json: null, raw: e.message }));

    if (body) {
      req.write(typeof body === 'string' ? body : JSON.stringify(body));
    }
    req.end();
  });
}

function assert(condition, message) {
  if (!condition) {
    const err = new Error(message);
    err.code = 'ASSERT_FAIL';
    throw err;
  }
}

(async () => {
  const { session, license } = parseArgs();
  const sessionId = String(session || '').trim();
  if (!sessionId) {
    console.error('Missing --session <X_SESSION_ID>');
    process.exitCode = 2;
    return;
  }

  let licenseId = String(license || '').trim();

  if (!licenseId) {
    const list = await requestJson('/api/admin/licenses?limit=5&page=1', {
      headers: { 'x-session-id': sessionId }
    });
    console.log(`GET ${list.url} -> ${list.status}`);
    assert(list.status === 200, `Admin list licenses failed: HTTP ${list.status}`);
    assert(list.json && (list.json.ok === true || list.json.success === true), `Admin list indicates failure: ${list.raw}`);
    const licenses = Array.isArray(list.json.licenses) ? list.json.licenses : [];
    assert(licenses.length > 0, 'No licenses found to test with');
    licenseId = String(licenses[0].id);
    console.log(`Using license id: ${licenseId}`);
  }

  const exp = await requestJson(`/api/admin/licenses/${encodeURIComponent(licenseId)}/license-file?ensure_active=true`, {
    headers: { 'x-session-id': sessionId }
  });
  console.log(`GET ${exp.url} -> ${exp.status}`);
  assert(exp.status === 200, `Export license-file failed: HTTP ${exp.status}`);
  assert(exp.json && typeof exp.json === 'object', `Expected JSON body, got: ${exp.raw}`);

  const payload = exp.json.payload && typeof exp.json.payload === 'object' ? exp.json.payload : null;
  assert(payload, 'Missing payload in exported license file');

  const businessId = String(payload.business_id || '').trim();
  const licenseKey = String(payload.license_key || '').trim();
  console.log(`payload.license_key=${licenseKey || '(missing)'}`);
  console.log(`payload.business_id=${businessId || '(missing)'}`);

  assert(businessId, 'Exported license file is missing payload.business_id');
  assert(exp.json.signature, 'Missing signature in exported license file');

  const pub = await requestJson(`/businesses/${encodeURIComponent(businessId)}/license`);
  console.log(`GET ${pub.url} -> ${pub.status}`);
  if (pub.status === 204) {
    console.log('Public business license: 204 (no active cloud token yet)');
  } else if (pub.status === 200) {
    if (pub.json) {
      console.log('Public business license JSON:', JSON.stringify(pub.json, null, 2).slice(0, 2500));
    } else {
      console.log(String(pub.raw || '').slice(0, 2500));
    }
  } else {
    console.log('Unexpected public status:', pub.status);
    console.log(String(pub.raw || '').slice(0, 1200));
  }

  console.log('OK: real backend export includes business_id');
})().catch((e) => {
  console.error('FAIL:', e && e.message ? e.message : e);
  process.exitCode = 1;
});
