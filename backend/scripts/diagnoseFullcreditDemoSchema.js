/**
 * Script de diagnóstico para verificar el esquema real de las tablas
 * que usa el flujo de demo de FullCredit.
 * 
 * Uso: node backend/scripts/diagnoseFullcreditDemoSchema.js
 */
const { pool } = require('../db/pool');

async function getColumns(table) {
  try {
    const res = await pool.query(
      `SELECT column_name, data_type, is_nullable, column_default
       FROM information_schema.columns
       WHERE table_name = $1
       ORDER BY ordinal_position`,
      [table]
    );
    return res.rows;
  } catch (e) {
    return { error: e.message, code: e.code };
  }
}

async function main() {
  console.log('=== DIAGNÓSTICO DE ESQUEMA FULLCREDIT DEMO ===\n');

  const tables = ['projects', 'customers', 'licenses', 'license_activations', 'demo_trials'];

  for (const table of tables) {
    console.log(`--- ${table} ---`);
    const cols = await getColumns(table);
    if (Array.isArray(cols)) {
      if (cols.length === 0) {
        console.log('  (tabla vacía o no existe)');
      } else {
        for (const col of cols) {
          console.log(`  ${col.column_name} (${col.data_type}) nullable=${col.is_nullable} default=${col.default || 'N/A'}`);
        }
      }
    } else {
      console.log(`  ERROR: ${cols.error} (${cols.code})`);
    }
    console.log('');
  }

  // Verificar proyecto FULLCREDIT
  console.log('--- Proyecto FULLCREDIT ---');
  const projRes = await pool.query("SELECT id, code, name, monthly_price, currency, demo_days, min_purchase_months, allow_demo, is_paid_project, is_active FROM projects WHERE code = 'FULLCREDIT'");
  if (projRes.rows.length > 0) {
    console.log('  Encontrado:', JSON.stringify(projRes.rows[0], null, 2));
  } else {
    console.log('  NO ENCONTRADO');
  }

  // Verificar migraciones aplicadas
  console.log('--- Migraciones aplicadas ---');
  const migRes = await pool.query('SELECT filename, applied_at FROM schema_migrations ORDER BY filename');
  for (const row of migRes.rows) {
    console.log(`  ${row.filename} (${row.applied_at})`);
  }

  await pool.end();
}

main().catch(err => {
  console.error('FATAL:', err);
  process.exit(1);
});
