/*
  Smoke test (public business license endpoint)

  Usage:
    node scripts/smoke-business-license.js --business <BUSINESS_ID>

  Optional:
    API_ORIGIN=https://api.fulltechrd.com node scripts/smoke-business-license.js --business <BUSINESS_ID>

  Expected:
    - 204: no active license
    - 200: { ok:true, license_token:..., plan:... }
*/

const https = require('https');

const API_ORIGIN = (process.env.API_ORIGIN || 'https://api.fulltechrd.com').replace(/\/$/, '');

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--business') out.business = args[++i];
  }
  return out;
}

function get(path) {
  return new Promise((resolve) => {
    const url = API_ORIGIN + path;
    https
      .get(url, (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve({ url, status: res.statusCode, body }));
      })
      .on('error', (e) => resolve({ url, status: 'ERR', body: e.message }));
  });
}

(async () => {
  const { business } = parseArgs();
  const id = String(business || '').trim();
  if (!id) {
    console.error('Missing --business <BUSINESS_ID>');
    process.exitCode = 2;
    return;
  }

  const r = await get(`/businesses/${encodeURIComponent(id)}/license`);
  console.log(`GET ${r.url} -> ${r.status}`);
  if (r.status === 204) {
    console.log('(No active license yet)');
    return;
  }

  try {
    console.log(JSON.stringify(JSON.parse(r.body), null, 2));
  } catch {
    console.log(String(r.body || '').slice(0, 1200));
  }
})();
