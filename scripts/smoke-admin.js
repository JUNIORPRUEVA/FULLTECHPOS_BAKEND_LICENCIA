/*
  Smoke test (admin endpoints) - requires a valid x-session-id.

  Usage:
    node scripts/smoke-admin.js --session <SESSION_ID>

  Optional:
    API_ORIGIN=https://api.fulltechrd.com node scripts/smoke-admin.js --session <SESSION_ID>

  Notes:
    - This does NOT store credentials.
    - It only verifies that /api/admin/customers and /api/admin/licenses respond and returns counts.
*/

const https = require('https');

const API_ORIGIN = (process.env.API_ORIGIN || 'https://api.fulltechrd.com').replace(/\/$/, '');

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--session') out.session = args[++i];
  }
  return out;
}

function requestJson(path, sessionId) {
  return new Promise((resolve) => {
    const url = API_ORIGIN + path;
    const req = https.request(
      url,
      {
        method: 'GET',
        headers: {
          'x-session-id': sessionId,
        },
      },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => {
          let json = null;
          try {
            json = JSON.parse(body);
          } catch {
            json = null;
          }
          resolve({ url, status: res.statusCode, json, body: body.slice(0, 1200) });
        });
      }
    );
    req.on('error', (e) => resolve({ url, status: 'ERR', json: null, body: e.message }));
    req.end();
  });
}

(async () => {
  const { session } = parseArgs();
  if (!session || !String(session).trim()) {
    console.error('Missing --session <SESSION_ID>');
    process.exitCode = 2;
    return;
  }

  const sessionId = String(session).trim();

  const endpoints = [
    '/api/admin/customers?limit=5&page=1',
    '/api/admin/licenses?limit=5&page=1',
  ];

  for (const path of endpoints) {
    const r = await requestJson(path, sessionId);
    console.log(`GET ${r.url} -> ${r.status}`);

    if (r.json) {
      const customersCount = Array.isArray(r.json.customers) ? r.json.customers.length : null;
      const licensesCount = Array.isArray(r.json.licenses) ? r.json.licenses.length : null;
      const total = typeof r.json.total !== 'undefined' ? r.json.total : null;

      if (customersCount !== null) console.log(`customers.length=${customersCount} total=${total}`);
      if (licensesCount !== null) console.log(`licenses.length=${licensesCount} total=${total}`);

      if (r.json.success === false || r.json.ok === false) {
        console.log('Response indicates failure:', r.json.message || r.json.error || r.json);
      }
    } else {
      console.log(r.body);
    }

    console.log('---');
  }
})();
