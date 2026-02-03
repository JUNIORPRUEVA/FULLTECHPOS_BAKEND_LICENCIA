const fs = require('fs');
const path = require('path');
const dotenvLocalPath = path.join(__dirname, '../../.env.local');
const dotenvPath = fs.existsSync(dotenvLocalPath)
  ? dotenvLocalPath
  : path.join(__dirname, '../../.env');
require('dotenv').config({ path: dotenvPath });
const { pool } = require('./pool');

async function run() {
  const migrationsDir = path.join(__dirname, 'migrations');
  const files = fs
    .readdirSync(migrationsDir)
    .filter(f => f.toLowerCase().endsWith('.sql'))
    .sort();

  if (files.length === 0) {
    console.log('No hay migraciones .sql en', migrationsDir);
    return;
  }

  const client = await pool.connect();
  try {
    for (const file of files) {
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
