/**
 * smoke-saas.js — Phase 6 comprehensive smoke test
 *
 * Tests ALL SaaS Phase 1-5 endpoints plus legacy license endpoints.
 * Requires a running backend and credentials via env or defaults.
 *
 * Usage:
 *   node scripts/smoke-saas.js
 *   API_ORIGIN=http://localhost:3013 node scripts/smoke-saas.js
 *   ADMIN_USERNAME=user ADMIN_PASSWORD=pass API_ORIGIN=... node scripts/smoke-saas.js
 *
 * Exit code: 0 = all pass, 1 = one or more failures, 2 = startup error
 */

'use strict';

const http = require('http');
const https = require('https');

const API_ORIGIN = String(process.env.API_ORIGIN || 'http://localhost:3000').replace(/\/$/, '');
const ADMIN_USER = process.env.ADMIN_USERNAME || 'fulltechsd@gmail.com';
const ADMIN_PASS = process.env.ADMIN_PASSWORD || 'Ayleen10';

const results = [];
let PASSED = 0;
let FAILED = 0;

// ─── HTTP helpers ──────────────────────────────────────────────────────────────

function makeRequest(method, path, { headers = {}, body } = {}) {
  return new Promise((resolve) => {
    const url = API_ORIGIN + path;
    const isHttps = url.startsWith('https');
    const mod = isHttps ? https : http;
    const parsed = new URL(url);

    const opts = {
      hostname: parsed.hostname,
      port: parsed.port || (isHttps ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method,
      headers: { 'Content-Type': 'application/json', ...headers }
    };

    const payload = body ? JSON.stringify(body) : null;
    if (payload) opts.headers['Content-Length'] = Buffer.byteLength(payload);

    const req = mod.request(opts, (res) => {
      let raw = '';
      res.on('data', (c) => (raw += c));
      res.on('end', () => {
        let json = null;
        try { json = JSON.parse(raw); } catch (_) {}
        resolve({ status: res.statusCode, json, raw: raw.slice(0, 500) });
      });
    });

    req.on('error', (e) => resolve({ status: 'ERR', json: null, raw: e.message }));
    if (payload) req.write(payload);
    req.end();
  });
}

// ─── assertion helpers ─────────────────────────────────────────────────────────

function assert(label, condition, detail = '') {
  if (condition) {
    PASSED++;
    results.push({ ok: true, label });
    process.stdout.write(`  ✓ ${label}\n`);
  } else {
    FAILED++;
    results.push({ ok: false, label, detail });
    process.stdout.write(`  ✗ ${label}${detail ? '  [' + detail + ']' : ''}\n`);
  }
}

// ─── test blocks ──────────────────────────────────────────────────────────────

async function testHealth() {
  console.log('\n[1] Health checks');
  const r = await makeRequest('GET', '/api/health');
  assert('GET /api/health → 200', r.status === 200, `status=${r.status}`);
  assert('health ok=true', r.json?.ok === true, `body=${r.raw}`);
}

async function login() {
  console.log('\n[2] Admin login');
  const r = await makeRequest('POST', '/api/login', { body: { username: ADMIN_USER, password: ADMIN_PASS } });
  assert('POST /api/login → 200', r.status === 200, `status=${r.status}`);
  assert('login returns sessionId', typeof r.json?.sessionId === 'string', `body=${r.raw}`);
  return r.json?.sessionId || null;
}

async function testBadLogin() {
  console.log('\n[3] Login security');
  const r = await makeRequest('POST', '/api/login', { body: { username: 'baduser', password: 'badpass' } });
  assert('POST /api/login bad creds → 401', r.status === 401, `status=${r.status}`);
  assert('bad login no sessionId', !r.json?.sessionId, `body=${r.raw}`);
}

async function testAdminProtection() {
  console.log('\n[4] Admin route protection (no session)');
  const endpoints = [
    '/api/admin/subscriptions?limit=1&offset=0',
    '/api/admin/product-plans?limit=1&offset=0',
    '/api/admin/payments?limit=1&offset=0',
    '/api/admin/saas-dashboard',
  ];
  for (const p of endpoints) {
    const r = await makeRequest('GET', p);
    assert(`GET ${p} without session → 401`, r.status === 401, `status=${r.status}`);
  }
  // Maintenance without session
  const r2 = await makeRequest('POST', '/api/admin/subscriptions/run-maintenance');
  assert('POST run-maintenance without session → 401', r2.status === 401, `status=${r2.status}`);
}

async function testProductPlans(sid) {
  console.log('\n[5] Product Plans API');
  const h = { 'x-session-id': sid };
  const r = await makeRequest('GET', '/api/admin/product-plans?limit=5&offset=0', { headers: h });
  assert('GET /api/admin/product-plans → 200', r.status === 200, `status=${r.status}`);
  assert('plans response ok=true', r.json?.ok === true || Array.isArray(r.json?.plans), `body=${r.raw}`);
  return Array.isArray(r.json?.data?.plans) ? r.json.data.plans[0] : (Array.isArray(r.json?.plans) ? r.json.plans[0] : null);
}

async function testSubscriptions(sid) {
  console.log('\n[6] Subscriptions API');
  const h = { 'x-session-id': sid };
  const r = await makeRequest('GET', '/api/admin/subscriptions?limit=5&offset=0', { headers: h });
  assert('GET /api/admin/subscriptions → 200', r.status === 200, `status=${r.status}`);
  const hasSubs = Array.isArray(r.json?.subscriptions) || Array.isArray(r.json?.data?.subscriptions);
  assert('subscriptions response has array', hasSubs, `body=${r.raw}`);
  const subs = r.json?.data?.subscriptions || r.json?.subscriptions || [];
  return subs[0] || null;
}

async function testPayments(sid) {
  console.log('\n[7] Payments API');
  const h = { 'x-session-id': sid };
  const r = await makeRequest('GET', '/api/admin/payments?limit=5&offset=0', { headers: h });
  assert('GET /api/admin/payments → 200', r.status === 200, `status=${r.status}`);
  const hasPay = Array.isArray(r.json?.payments) || Array.isArray(r.json?.data?.payments);
  assert('payments response has array', hasPay, `body=${r.raw}`);
}

async function testSaasDashboard(sid) {
  console.log('\n[9] SaaS Dashboard API');
  const h = { 'x-session-id': sid };
  const r = await makeRequest('GET', '/api/admin/saas-dashboard', { headers: h });
  assert('GET /api/admin/saas-dashboard → 200', r.status === 200, `status=${r.status}`);
  assert('dashboard ok=true', r.json?.ok === true, `body=${r.raw}`);
  const d = r.json?.data;
  assert('dashboard has total_companies', typeof d?.total_companies === 'number', `d=${JSON.stringify(d)}`);
  assert('dashboard has active_subscriptions', typeof d?.active_subscriptions === 'number', `d=${JSON.stringify(d)}`);
  assert('dashboard has expired_subscriptions', typeof d?.expired_subscriptions === 'number', `d=${JSON.stringify(d)}`);
  assert('dashboard has monthly_revenue_estimate', typeof d?.monthly_revenue_estimate === 'number', `d=${JSON.stringify(d)}`);
  assert('dashboard has clients_near_expiration array', Array.isArray(d?.clients_near_expiration), `d=${JSON.stringify(d)}`);
  assert('dashboard has revenue_by_product_or_project array', Array.isArray(d?.revenue_by_product_or_project), `d=${JSON.stringify(d)}`);
}

async function testMaintenance(sid) {
  console.log('\n[10] Run maintenance endpoint');
  const h = { 'x-session-id': sid };
  const r = await makeRequest('POST', '/api/admin/subscriptions/run-maintenance', { headers: h, body: {} });
  assert('POST /api/admin/subscriptions/run-maintenance → 200', r.status === 200, `status=${r.status}`);
  assert('maintenance ok=true', r.json?.ok === true, `body=${r.raw}`);
  const d = r.json?.data;
  assert('maintenance has expired_count', typeof d?.expired_count === 'number', `d=${JSON.stringify(d)}`);
  assert('maintenance has licenses_blocked_count', typeof d?.licenses_blocked_count === 'number', `d=${JSON.stringify(d)}`);
}

async function testLegacyAdmin(sid) {
  console.log('\n[11] Legacy admin endpoints');
  const h = { 'x-session-id': sid };
  const endpoints = [
    ['/api/admin/customers?limit=1&page=1', 'customers'],
    ['/api/admin/licenses?limit=1&page=1', 'licenses'],
    // Note: /api/admin/businesses only has POST /:id/activate — no list endpoint
    ['/api/admin/projects', 'projects'],
  ];
  for (const [p, label] of endpoints) {
    const r = await makeRequest('GET', p, { headers: h });
    assert(`GET ${p} (${label}) → 200`, r.status === 200, `status=${r.status}`);
  }
}

async function testPublicLicenseEndpoints() {
  console.log('\n[12] Public license endpoints (legacy)');

  // check with empty body → 400 (missing key)
  const rCheck = await makeRequest('POST', '/api/licenses/check', { body: {} });
  assert('POST /api/licenses/check empty → 400', rCheck.status === 400, `status=${rCheck.status}`);
  assert('check error has message', typeof rCheck.json?.message === 'string', `body=${rCheck.raw}`);

  // activate with empty body → 400
  const rActivate = await makeRequest('POST', '/api/licenses/activate', { body: {} });
  assert('POST /api/licenses/activate empty → 400', rActivate.status === 400, `status=${rActivate.status}`);
  assert('activate error has message', typeof rActivate.json?.message === 'string', `body=${rActivate.raw}`);

  // start-demo with empty body → 400
  const rDemo = await makeRequest('POST', '/api/licenses/start-demo', { body: {} });
  assert('POST /api/licenses/start-demo empty → 400', rDemo.status === 400, `status=${rDemo.status}`);
}

async function testV2Validation() {
  console.log('\n[13] V2 license validation');

  // Empty body → 200 with can_access:false (v2 treats missing key as not_found, not a 400)
  const r400 = await makeRequest('POST', '/api/v2/licenses/validate', { body: {} });
  assert('POST /api/v2/licenses/validate empty → 200 (not_found)', r400.status === 200, `status=${r400.status}`);
  assert('v2 empty body has success field', typeof r400.json?.success !== 'undefined', `body=${r400.raw}`);

  // Fake key → 200 with can_access:false, status:not_found (v2 does not return 404)
  const rFake = await makeRequest('POST', '/api/v2/licenses/validate', {
    body: { license_key: 'smoke-test-invalid-key-0000' }
  });
  assert('POST v2/validate fake key → 200', rFake.status === 200, `status=${rFake.status}`);
  assert('v2 fake-key has can_access=false', rFake.json?.can_access === false, `body=${rFake.raw}`);
  assert('v2 fake-key status is not_found', rFake.json?.status === 'not_found', `body=${rFake.raw}`);
  assert('v2 no stack trace exposed', !String(rFake.raw).includes('at Object.'), `body=${rFake.raw}`);
}

async function testAdminPages() {
  console.log('\n[14] Admin HTML pages');
  const pages = [
    '/admin/login.html',
    '/admin/dashboard.html',
    '/admin/admin-hub.html',
    '/admin/saas-dashboard.html',
    '/admin/subscriptions.html',
    '/admin/payments.html',
    '/admin/product-plans.html',
    '/admin/platform-users.html',
  ];
  for (const p of pages) {
    const r = await makeRequest('GET', p);
    assert(`GET ${p} → 200`, r.status === 200, `status=${r.status}`);
  }
}

async function testPlatformUsers(sid) {
  console.log('\n[15] Platform Users & Roles API');
  const h = { 'x-session-id': sid };
  const rU = await makeRequest('GET', '/api/admin/platform-users?limit=5&offset=0', { headers: h });
  assert('GET /api/admin/platform-users → 200', rU.status === 200, `status=${rU.status}`);
  const rR = await makeRequest('GET', '/api/admin/roles?limit=5&offset=0', { headers: h });
  assert('GET /api/admin/roles → 200', rR.status === 200, `status=${rR.status}`);
}

// ─── main ─────────────────────────────────────────────────────────────────────

(async () => {
  console.log('='.repeat(60));
  console.log('  SMOKE TEST — SaaS Manager Phase 1-5');
  console.log(`  Origin: ${API_ORIGIN}`);
  console.log('='.repeat(60));

  await testHealth();
  await testBadLogin();
  await testAdminProtection();

  const sid = await login();
  if (!sid) {
    console.error('\n[FATAL] Could not obtain session. Aborting remaining tests.');
    process.exitCode = 2;
    return;
  }

  await testProductPlans(sid);
  await testSubscriptions(sid);
  await testPayments(sid);
  await testSaasDashboard(sid);
  await testMaintenance(sid);
  await testLegacyAdmin(sid);
  await testPublicLicenseEndpoints();
  await testV2Validation();
  await testAdminPages();
  await testPlatformUsers(sid);

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log(`  RESULTS: ${PASSED} passed, ${FAILED} failed`);
  if (FAILED > 0) {
    console.log('\n  FAILURES:');
    results.filter(r => !r.ok).forEach(r => console.log(`    ✗ ${r.label}${r.detail ? '  [' + r.detail + ']' : ''}`));
  }
  console.log('='.repeat(60));

  process.exitCode = FAILED > 0 ? 1 : 0;
})();
