const fs = require('fs');
const path = require('path');

// Load env (SAFER DEFAULT): use .env unless explicitly told otherwise.
// This avoids accidentally connecting to localhost from .env.local placeholders.
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

const KEEP_TABLES = new Set([
  'customers',
  'licenses',
  'license_activations',
  'license_config',
  'projects'
]);

function usage() {
  console.log(`
Usage:
  node backend/db/cleanupLicenseDb.js preview
  node backend/db/cleanupLicenseDb.js list
  node backend/db/cleanupLicenseDb.js move --yes
  node backend/db/cleanupLicenseDb.js drop --yes

Notes:
- preview/list are safe (read-only).
- move relocates non-license tables from schema public -> _trash (reversible).
- drop removes non-license tables from schema public (irreversible).
`);
}

async function getExtraTables(client) {
  const res = await client.query(
    `SELECT tablename
     FROM pg_tables
     WHERE schemaname = 'public'
     ORDER BY tablename`
  );
  const all = res.rows.map(r => r.tablename);
  const extra = all.filter(t => !KEEP_TABLES.has(t));
  return { all, extra };
}

async function preview(client) {
  const res = await client.query(
    `SELECT
       s.schemaname,
       s.relname AS tablename,
       s.n_live_tup::bigint AS approx_rows,
       pg_size_pretty(pg_total_relation_size(format('%I.%I', s.schemaname, s.relname)::regclass)) AS total_size
     FROM pg_stat_user_tables s
     WHERE s.schemaname = 'public'
     ORDER BY pg_total_relation_size(format('%I.%I', s.schemaname, s.relname)::regclass) DESC`
  );

  console.table(res.rows);
}

async function list(client) {
  const { all, extra } = await getExtraTables(client);

  console.log(`\nSchema public: ${all.length} tablas`);
  console.log(`Tablas de licencias (keep): ${Array.from(KEEP_TABLES).join(', ')}`);

  if (!extra.length) {
    console.log('\n✅ No hay tablas extra para limpiar.');
    return;
  }

  console.log(`\n⚠️ Tablas extra (${extra.length}) que NO son del módulo de licencias:`);
  for (const t of extra) console.log(`- ${t}`);
}

async function moveToTrash(client, { yes }) {
  if (!yes) {
    throw new Error('Falta confirmación: agrega --yes para ejecutar MOVE a _trash.');
  }

  const { extra } = await getExtraTables(client);
  if (!extra.length) {
    console.log('✅ No hay tablas extra para mover.');
    return;
  }

  await client.query('BEGIN');
  try {
    await client.query('CREATE SCHEMA IF NOT EXISTS _trash');
    for (const t of extra) {
      await client.query(`ALTER TABLE public.${t} SET SCHEMA _trash`);
      console.log(`Moved: public.${t} -> _trash.${t}`);
    }
    await client.query('COMMIT');
    console.log('✅ Listo. Tablas extra movidas a schema _trash.');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  }
}

async function dropExtra(client, { yes }) {
  if (!yes) {
    throw new Error('Falta confirmación: agrega --yes para ejecutar DROP (irreversible).');
  }

  const { extra } = await getExtraTables(client);
  if (!extra.length) {
    console.log('✅ No hay tablas extra para borrar.');
    return;
  }

  await client.query('BEGIN');
  try {
    for (const t of extra) {
      await client.query(`DROP TABLE IF EXISTS public.${t} CASCADE`);
      console.log(`Dropped: public.${t}`);
    }
    await client.query('COMMIT');
    console.log('✅ Listo. Tablas extra borradas.');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  }
}

async function main() {
  const args = process.argv.slice(2);
  const cmd = (args[0] || '').toLowerCase();
  const yes = args.includes('--yes');

  if (!cmd || cmd === '--help' || cmd === '-h' || cmd === 'help') {
    usage();
    process.exit(0);
  }

  const client = await pool.connect();
  try {
    if (cmd === 'preview') return await preview(client);
    if (cmd === 'list') return await list(client);
    if (cmd === 'move') return await moveToTrash(client, { yes });
    if (cmd === 'drop') return await dropExtra(client, { yes });

    usage();
    process.exitCode = 2;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch(err => {
  console.error('❌ cleanupLicenseDb error:', err?.message || err);
  process.exit(1);
});
