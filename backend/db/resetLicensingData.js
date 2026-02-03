const fs = require('fs');
const path = require('path');

// Load env (SAFER DEFAULT): use .env unless explicitly told otherwise.
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

const TABLES = [
  'license_activations',
  'licenses',
  'customers'
];

async function counts(client) {
  const rows = [];
  for (const t of ['projects', 'license_config', ...TABLES]) {
    try {
      const res = await client.query(`SELECT COUNT(*)::bigint AS count FROM ${t}`);
      rows.push({ table: t, rows: Number(res.rows[0]?.count || 0) });
    } catch (e) {
      rows.push({ table: t, rows: null, error: e?.message || String(e) });
    }
  }
  console.table(rows);
}

function usage() {
  console.log(`
Usage:
  node backend/db/resetLicensingData.js preview
  node backend/db/resetLicensingData.js reset --yes [--drop-nondefault-projects]

What it does:
- preview: shows row counts for licensing tables.
- reset: deletes licensing data (activations, licenses, customers).
  Optionally deletes projects except DEFAULT (only safe after licenses are deleted).

This does NOT drop tables.
`);
}

async function reset(client, { yes, dropNonDefaultProjects }) {
  if (!yes) throw new Error('Falta confirmación: agrega --yes para ejecutar reset.');

  await client.query('BEGIN');
  try {
    // PostgreSQL requiere truncar juntas las tablas relacionadas por FK.
    await client.query('TRUNCATE TABLE license_activations, licenses, customers');

    if (dropNonDefaultProjects) {
      // Keep DEFAULT project for backward compatibility
      await client.query("DELETE FROM projects WHERE code <> 'DEFAULT'");
    }

    await client.query('COMMIT');
    console.log('✅ Reset completado.');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  }
}

async function main() {
  const args = process.argv.slice(2);
  const cmd = (args[0] || '').toLowerCase();
  const yes = args.includes('--yes');
  const dropNonDefaultProjects = args.includes('--drop-nondefault-projects');

  if (!cmd || cmd === 'help' || cmd === '--help' || cmd === '-h') {
    usage();
    process.exit(0);
  }

  const client = await pool.connect();
  try {
    if (cmd === 'preview') {
      await counts(client);
      return;
    }
    if (cmd === 'reset') {
      await reset(client, { yes, dropNonDefaultProjects });
      await counts(client);
      return;
    }

    usage();
    process.exitCode = 2;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch(err => {
  console.error('❌ resetLicensingData error:', err?.message || err);
  process.exit(1);
});
