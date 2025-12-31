/*
  Sync smoke test (Node 18+).

  What it does:
  - Creates a company
  - Links an existing license (by license_key) to that company (company_licenses)
  - Executes /api/sync/push with sample rows (clients, products)
  - Executes /api/sync/pull since epoch

  Usage:
  - Ensure backend is running on http://localhost:3000
  - Ensure migrations 003 + 004 were applied
  - Ensure the license_key is already activated for the device_id (via /api/licenses/activate)

  Run:
    node backend/modules/sync/sync_smoke_test.js DEMO-XXXX device-123
*/

const { pool } = require('../../db/pool');

async function main() {
  const [licenseKey, deviceId] = process.argv.slice(2);
  if (!licenseKey || !deviceId) {
    throw new Error('Usage: node backend/modules/sync/sync_smoke_test.js <license_key> <device_id>');
  }

  // 1) Find license id
  const licRes = await pool.query('SELECT id FROM licenses WHERE license_key = $1', [licenseKey]);
  const licenseId = licRes.rows[0]?.id;
  if (!licenseId) throw new Error('license_key not found in DB');

  // 2) Create company
  const compRes = await pool.query(
    `INSERT INTO companies (name)
     VALUES ($1)
     RETURNING id`,
    ['Empresa Sync QA']
  );
  const companyId = compRes.rows[0].id;

  // 3) Link license -> company
  await pool.query(
    `INSERT INTO company_licenses (company_id, license_id)
     VALUES ($1, $2)
     ON CONFLICT (license_id) DO NOTHING`,
    [companyId, licenseId]
  );

  // 4) Call sync endpoints
  const base = 'http://localhost:3000';
  const headers = {
    'content-type': 'application/json',
    'x-license-key': licenseKey,
    'x-device-id': deviceId
  };

  const now = new Date().toISOString();
  const pushBody = {
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
          created_at_ms: Date.now(),
          updated_at_ms: Date.now(),
          updated_at: now,
          is_deleted: false
        }
      ],
      products: [
        {
          id: 1,
          code: 'P-SYNC-1',
          name: 'Producto Sync',
          image_path: null,
          category_id: null,
          supplier_id: null,
          purchase_price: 10.0,
          sale_price: 15.0,
          stock: 5.0,
          stock_min: 0.0,
          is_active: true,
          deleted_at_ms: null,
          created_at_ms: Date.now(),
          updated_at_ms: Date.now(),
          updated_at: now,
          is_deleted: false
        }
      ]
    }
  };

  const pushRes = await fetch(`${base}/api/sync/push`, {
    method: 'POST',
    headers,
    body: JSON.stringify(pushBody)
  });
  const pushJson = await pushRes.json();

  const pullRes = await fetch(`${base}/api/sync/pull?last_sync_at=${encodeURIComponent(new Date(0).toISOString())}`, {
    method: 'GET',
    headers
  });
  const pullJson = await pullRes.json();

  console.log(JSON.stringify({ companyId, push: pushJson, pullTables: Object.keys(pullJson.tables || {}) }, null, 2));
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
