/*
  Sync E2E test.

  It validates the full flow without requiring manual steps:
  - start demo license (creates customer+license)
  - activate license for a device
  - create a company
  - link license -> company (company_licenses)
  - /api/sync/push + /api/sync/pull success
  - admin login + block license
  - /api/sync/pull must fail (403)

  Usage:
    node backend/modules/sync/sync_e2e_test.js

  Optional env:
    BASE_URL=http://localhost:3000
    ADMIN_USERNAME=...
    ADMIN_PASSWORD=...
*/

const path = require('path');
const fs = require('fs');

const dotenvLocalPath = path.join(__dirname, '../../../.env.local');
const dotenvPath = fs.existsSync(dotenvLocalPath) ? dotenvLocalPath : path.join(__dirname, '../../../.env');
require('dotenv').config({ path: dotenvPath });

const { pool } = require('../../db/pool');

function assert(value, message) {
  if (!value) throw new Error(message);
}

async function postJson(url, body, headers = {}) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body)
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  return { status: res.status, ok: res.ok, json };
}

async function patchJson(url, body, headers = {}) {
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body)
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  return { status: res.status, ok: res.ok, json };
}

async function getJson(url, headers = {}) {
  const res = await fetch(url, {
    method: 'GET',
    headers
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  return { status: res.status, ok: res.ok, json };
}

async function main() {
  const baseUrl = (process.env.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
  const adminUsername = process.env.ADMIN_USERNAME || 'fulltechsd@gmail.com';
  const adminPassword = process.env.ADMIN_PASSWORD || 'Ayleen10';

  const deviceId = `sync-e2e-${Math.random().toString(16).slice(2, 10)}`;

  // 1) start-demo
  const startDemoRes = await postJson(`${baseUrl}/api/licenses/start-demo`, {
    nombre_negocio: 'SYNC E2E',
    contacto_nombre: 'QA',
    contacto_email: `sync-e2e-${Date.now()}@example.com`,
    contacto_telefono: '999999999',
    device_id: deviceId
  });
  assert(startDemoRes.ok, `start-demo failed: ${startDemoRes.status} ${JSON.stringify(startDemoRes.json)}`);
  const licenseKey = startDemoRes.json?.license_key;
  assert(licenseKey, 'start-demo did not return license_key');

  // 2) activate (idempotent)
  const activateRes = await postJson(`${baseUrl}/api/licenses/activate`, { license_key: licenseKey, device_id: deviceId });
  assert(activateRes.ok, `activate failed: ${activateRes.status} ${JSON.stringify(activateRes.json)}`);

  // 3) find licenseId + create company + link
  const licRes = await pool.query('SELECT id FROM licenses WHERE license_key = $1', [licenseKey]);
  const licenseId = licRes.rows[0]?.id;
  assert(licenseId, 'license_key not found in DB after start-demo');

  const compRes = await pool.query('INSERT INTO companies(name) VALUES($1) RETURNING id', [`Empresa Sync E2E ${Date.now()}`]);
  const companyId = compRes.rows[0]?.id;
  assert(companyId, 'failed to create company');

  await pool.query(
    'INSERT INTO company_licenses(company_id, license_id) VALUES($1,$2) ON CONFLICT (license_id) DO UPDATE SET company_id=EXCLUDED.company_id',
    [companyId, licenseId]
  );

  // 4) push + pull
  const syncHeaders = { 'x-license-key': licenseKey, 'x-device-id': deviceId };
  const now = new Date().toISOString();
  const nowMs = Date.now();

  const pushRes = await postJson(
    `${baseUrl}/api/sync/push`,
    {
      last_sync_at: new Date(0).toISOString(),
      tables: {
        clients: [
          {
            id: 1,
            nombre: 'Cliente Sync',
            telefono: '8090000000',
            direccion: 'Av. Principal',
            rnc: null,
            cedula: null,
            is_active: true,
            has_credit: false,
            deleted_at_ms: null,
            created_at_ms: nowMs,
            updated_at_ms: nowMs,
            updated_at: now,
            is_deleted: false
          }
        ]
      }
    },
    syncHeaders
  );
  assert(pushRes.ok, `sync push failed: ${pushRes.status} ${JSON.stringify(pushRes.json)}`);

  const pullRes = await getJson(`${baseUrl}/api/sync/pull?last_sync_at=${encodeURIComponent(new Date(0).toISOString())}`, syncHeaders);
  assert(pullRes.ok, `sync pull failed: ${pullRes.status} ${JSON.stringify(pullRes.json)}`);

  // 5) admin login
  const loginRes = await postJson(`${baseUrl}/api/login`, { username: adminUsername, password: adminPassword });
  assert(loginRes.ok, `admin login failed: ${loginRes.status} ${JSON.stringify(loginRes.json)}`);
  const sessionId = loginRes.json?.sessionId;
  assert(sessionId, 'admin login did not return sessionId');

  // 6) block license
  const blockRes = await patchJson(`${baseUrl}/api/admin/licenses/${licenseId}/bloquear`, {}, { 'x-session-id': sessionId });
  assert(blockRes.ok, `block failed: ${blockRes.status} ${JSON.stringify(blockRes.json)}`);

  // 7) pull must fail
  const pullAfterRes = await getJson(
    `${baseUrl}/api/sync/pull?last_sync_at=${encodeURIComponent(new Date(0).toISOString())}`,
    syncHeaders
  );

  // 8) unblock license
  const unblockRes = await patchJson(`${baseUrl}/api/admin/licenses/${licenseId}/desbloquear`, {}, { 'x-session-id': sessionId });
  assert(unblockRes.ok, `unblock failed: ${unblockRes.status} ${JSON.stringify(unblockRes.json)}`);

  // 9) pull should succeed again
  const pullAfterUnblockRes = await getJson(
    `${baseUrl}/api/sync/pull?last_sync_at=${encodeURIComponent(new Date(0).toISOString())}`,
    syncHeaders
  );

  const summary = {
    ok: true,
    baseUrl,
    licenseKey,
    deviceId,
    licenseId,
    companyId,
    pushOk: pushRes.json?.ok === true,
    pullOk: pullRes.json?.ok === true,
    pullClientsCount: Array.isArray(pullRes.json?.tables?.clients) ? pullRes.json.tables.clients.length : null,
    pullAfterBlockStatus: pullAfterRes.status,
    pullAfterBlockBody: pullAfterRes.json,
    pullAfterUnblockStatus: pullAfterUnblockRes.status,
    pullAfterUnblockOk: pullAfterUnblockRes.ok,
    pullAfterUnblockBody: pullAfterUnblockRes.json
  };

  // Expect blocked license -> 403 (or at least not ok)
  if (pullAfterRes.status !== 403) {
    summary.ok = false;
  }

  // Expect unblocked license -> ok
  if (!pullAfterUnblockRes.ok) {
    summary.ok = false;
  }

  console.log(JSON.stringify(summary, null, 2));

  if (!summary.ok) {
    process.exit(2);
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    try {
      await pool.end();
    } catch (_) {
      // ignore
    }
  });
