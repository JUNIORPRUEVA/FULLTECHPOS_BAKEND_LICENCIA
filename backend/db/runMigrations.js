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
  console.error('❌ Error corriendo migraciones:', err.message);
  process.exit(1);
});
