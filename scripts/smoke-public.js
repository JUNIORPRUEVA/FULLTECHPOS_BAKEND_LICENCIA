/*
  Smoke test (public endpoints)
  Usage:
    node scripts/smoke-public.js
  Optional:
    API_ORIGIN=https://api.fulltechrd.com node scripts/smoke-public.js
*/

const https = require('https');

const API_ORIGIN = (process.env.API_ORIGIN || 'https://api.fulltechrd.com').replace(/\/$/, '');

function get(path) {
  return new Promise((resolve) => {
    const url = API_ORIGIN + path;
    https
      .get(url, (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => {
          resolve({ url, status: res.statusCode, body: body.slice(0, 1000) });
        });
      })
      .on('error', (e) => resolve({ url: API_ORIGIN + path, status: 'ERR', body: e.message }));
  });
}

(async () => {
  const checks = ['/api/health', '/api/health/db', '/health'];
  for (const path of checks) {
    const r = await get(path);
    console.log(`GET ${r.url} -> ${r.status}`);
    console.log(r.body);
    console.log('---');
  }
})();
