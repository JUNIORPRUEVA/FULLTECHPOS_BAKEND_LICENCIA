const fs = require('fs');
const path = require('path');

// Load env (SAFER DEFAULT): use .env unless explicitly told otherwise.
// This avoids accidentally connecting to localhost when .env.local contains placeholders.
const rootDir = path.join(__dirname, '../..');

function resolveDotenvPath() {
  const override = process.env.DOTENV_PATH;
  if (override) {
    return path.isAbsolute(override) ? override : path.join(rootDir, override);
  }

  const useLocal = String(process.env.USE_DOTENV_LOCAL || '').trim() === '1';
  const envLocal = path.join(rootDir, '.env.local');
  const env = path.join(rootDir, '.env');

  if (useLocal && fs.existsSync(envLocal)) return envLocal;
  return env;
}

const dotenvPath = resolveDotenvPath();
require('dotenv').config({ path: dotenvPath });
console.log(`Using env file: ${dotenvPath}`);
const { pool } = require('./pool');

async function run() {
  const migrationsDir = path.join(__dirname, 'migrations');
  const files = fs
    .readdirSync(migrationsDir)
    .filter(f => f.toLowerCase().endsWith('.sql'))
    .sort();

  const licenseOnly = String(process.env.LICENSE_ONLY || '').trim() === '1';
  const allowlist = new Set([
    '001_create_license_tables.sql',
    '002_create_license_config.sql',
    '007_create_projects_and_project_scoping.sql',
    '008_add_customer_business_role.sql'
  ]);

  const selectedFiles = licenseOnly
    ? files.filter(f => allowlist.has(f))
    : files;

  if (files.length === 0) {
    console.log('No hay migraciones .sql en', migrationsDir);
    return;
  }

  if (licenseOnly) {
    const skipped = files.filter(f => !allowlist.has(f));
    console.log('ℹ️ LICENSE_ONLY=1: ejecutando solo migraciones de licencias.');
    console.log('   Incluidas:', selectedFiles.join(', ') || '(ninguna)');
    if (skipped.length) console.log('   Omitidas:', skipped.join(', '));
  }

  const client = await pool.connect();
  try {
    for (const file of selectedFiles) {
      const fullPath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(fullPath, 'utf8');
      console.log('Ejecutando migración:', file);
      await client.query(sql);
    }
    console.log('✅ Migraciones completadas');
  } finally {
    client.release();
    await pool.end();
  }
}

run().catch(err => {
  const code = err && (err.code || err.name) ? String(err.code || err.name) : '';
  const msg = err && err.message ? String(err.message) : '';
  console.error('❌ Error corriendo migraciones:', code ? `[${code}]` : '', msg);
  if (err) {
    // AggregateError (ECONNREFUSED) puede venir con details en err.errors
    if (Array.isArray(err.errors) && err.errors.length) {
      for (const e of err.errors) {
        const eCode = e && e.code ? String(e.code) : '';
        const eMsg = e && e.message ? String(e.message) : '';
        console.error('  -', eCode ? `[${eCode}]` : '', eMsg);
      }
    } else {
      console.error(err);
    }
  }
  process.exit(1);
});
