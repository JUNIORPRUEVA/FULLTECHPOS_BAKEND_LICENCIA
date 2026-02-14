/*
  Smoke test (admin activate business -> public license token)

  Usage:
    node scripts/smoke-activate-business.js --session <SESSION_ID> --business <BUSINESS_ID> [--project FULLPOS] [--license <LICENSE_ID>]

  Optional:
    API_ORIGIN=https://api.fulltechrd.com node scripts/smoke-activate-business.js --session ...

  What it does:
    1) POST /api/admin/businesses/:business_id/activate
    2) GET  /businesses/:business_id/license
*/

const https = require('https');

const API_ORIGIN = (process.env.API_ORIGIN || 'https://api.fulltechrd.com').replace(/\/$/, '');

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--session') out.session = args[++i];
    else if (a === '--business') out.business = args[++i];
    else if (a === '--project') out.project = args[++i];
    else if (a === '--license') out.license = args[++i];
  }
  return out;
}

function postJson(path, sessionId, payload) {
  return new Promise((resolve) => {
    const url = new URL(API_ORIGIN + path);
    const body = JSON.stringify(payload || {});

    const req = https.request(
      {
        method: 'POST',
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body),
          'x-session-id': sessionId,
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => resolve({ status: res.statusCode, body: data }));
      }
    );

    req.on('error', (e) => resolve({ status: 'ERR', body: e.message }));
    req.write(body);
    req.end();
  });
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
  const { session, business, project, license } = parseArgs();

  const sessionId = String(session || '').trim();
  const businessId = String(business || '').trim();

  if (!sessionId) {
    console.error('Missing --session <SESSION_ID>');
    process.exitCode = 2;
    return;
  }
  if (!businessId) {
    console.error('Missing --business <BUSINESS_ID>');
    process.exitCode = 2;
    return;
  }

  const payload = {};
  if (project) payload.project_code = String(project).trim();
  if (license) payload.license_id = String(license).trim();

  const activatePath = `/api/admin/businesses/${encodeURIComponent(businessId)}/activate`;
  const activateRes = await postJson(activatePath, sessionId, payload);

  console.log(`POST ${API_ORIGIN}${activatePath} -> ${activateRes.status}`);
  try {
    console.log(JSON.stringify(JSON.parse(activateRes.body), null, 2));
  } catch {
    console.log(String(activateRes.body || '').slice(0, 1200));
  }

  console.log('---');

  const lic = await get(`/businesses/${encodeURIComponent(businessId)}/license`);
  console.log(`GET ${lic.url} -> ${lic.status}`);
  if (lic.status === 204) {
    console.log('(No active license yet)');
    return;
  }
  try {
    console.log(JSON.stringify(JSON.parse(lic.body), null, 2));
  } catch {
    console.log(String(lic.body || '').slice(0, 1200));
  }
})();
