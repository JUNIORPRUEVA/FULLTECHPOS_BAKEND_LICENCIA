/**
 * seed-daleventas-project.js — Provisiona el Project "DaleVentas POS" (project mode).
 *
 * Este script ESCRIBE en `projects`. Reglas de seguridad:
 *   - Es idempotente: si ya existe un proyecto con el code indicado, NO hace nada.
 *   - No borra, renombra ni desactiva ningún proyecto existente.
 *   - No toca licencias, pagos, trials, usuarios ni datos de DaleVentas.
 *   - No inventa datos comerciales: la configuración de facturación debe venir
 *     de un proyecto origen (`--billing-from=CODE`) o de valores explícitos.
 *   - Requiere CONFIRM_SEED_DALEVENTAS=1 para escribir (o --dry-run para simular).
 *
 * Uso (ejecutar primero en entorno seguro/local/UAT):
 *   CONFIRM_SEED_DALEVENTAS=1 node scripts/seed-daleventas-project.js --billing-from=FULLPOS
 *   CONFIRM_SEED_DALEVENTAS=1 node scripts/seed-daleventas-project.js --monthly-price=35 --currency=USD
 *   node scripts/seed-daleventas-project.js --dry-run
 */

'use strict';

require('dotenv').config();
const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL;
const sslMode = process.env.PGSSLMODE || '';
const pool = new Pool(
  connectionString
    ? {
        connectionString,
        ssl: sslMode.toLowerCase() === 'require' ? { rejectUnauthorized: false } : undefined
      }
    : {
        host: process.env.PGHOST,
        port: process.env.PGPORT ? Number(process.env.PGPORT) : undefined,
        user: process.env.PGUSER,
        password: process.env.PGPASSWORD,
        database: process.env.PGDATABASE
      }
);

function normalizeCode(code) {
  return String(code || '').trim().toUpperCase();
}

function parseArgs(argv) {
  const args = { code: 'DALEVENTAS', name: 'DaleVentas POS', dryRun: false };
  for (const raw of argv) {
    const [key, ...rest] = raw.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--code':
        args.code = value;
        break;
      case '--name':
        args.name = value;
        break;
      case '--billing-from':
        args.billingFrom = normalizeCode(value);
        break;
      case '--monthly-price':
        args.monthlyPrice = Number(value);
        break;
      case '--currency':
        args.currency = String(value || '').trim().toUpperCase();
        break;
      case '--demo-days':
        args.demoDays = Number(value);
        break;
      case '--min-months':
        args.minPurchaseMonths = Number(value);
        break;
      case '--paid':
        args.isPaidProject = value !== 'false';
        break;
      case '--allow-demo':
        args.allowDemo = value !== 'false';
        break;
      case '--dry-run':
        args.dryRun = true;
        break;
      default:
        break;
    }
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const code = normalizeCode(args.code);
  const name = String(args.name || '').trim();

  console.log('\n=== APPYRA — PROVISIONAR PROJECT DALEVENTAS ===\n');
  console.log(`code objetivo: ${code}`);
  console.log(`name objetivo: ${name}`);

  if (!code || !name) {
    throw new Error('code y name son requeridos');
  }

  const existing = await pool.query('SELECT id, code, name, is_active FROM projects WHERE UPPER(code) = $1', [
    code
  ]);
  if (existing.rowCount > 0) {
    const project = existing.rows[0];
    console.log('\nYa existe un proyecto con ese code. No se crea nada (sin duplicados).');
    console.log(`  id: ${project.id}`);
    console.log(`  code: ${project.code}`);
    console.log(`  name: ${project.name}`);
    console.log(`  is_active: ${project.is_active}`);
    return;
  }

  // Columnas reales de `projects` (para no asumir el esquema).
  const colsRes = await pool.query(
    `SELECT column_name FROM information_schema.columns
     WHERE table_schema='public' AND table_name='projects'`
  );
  const columns = new Set(colsRes.rows.map((row) => row.column_name));

  let billing;
  if (args.billingFrom) {
    const source = await pool.query(
      `SELECT code, monthly_price, currency, demo_days, min_purchase_months,
              is_paid_project, allow_demo
       FROM projects WHERE UPPER(code) = $1`,
      [args.billingFrom]
    );
    if (source.rowCount === 0) {
      throw new Error(
        `No existe el proyecto origen ${args.billingFrom}. ` +
          'Indica otro con --billing-from=CODE o pasa valores explícitos (--monthly-price, --currency...).'
      );
    }
    const row = source.rows[0];
    billing = {
      monthly_price: row.monthly_price,
      currency: row.currency,
      demo_days: row.demo_days,
      min_purchase_months: row.min_purchase_months,
      is_paid_project: row.is_paid_project,
      allow_demo: row.allow_demo,
      source: row.code
    };
  } else {
    if (!Number.isFinite(args.monthlyPrice) || !args.currency) {
      throw new Error(
        'Falta la configuración comercial. Usa --billing-from=CODE (recomendado) ' +
          'o valores explícitos: --monthly-price=35 --currency=USD [--demo-days=7] [--min-months=3].'
      );
    }
    billing = {
      monthly_price: args.monthlyPrice,
      currency: args.currency,
      demo_days: Number.isFinite(args.demoDays) ? args.demoDays : 7,
      min_purchase_months: Number.isFinite(args.minPurchaseMonths) ? args.minPurchaseMonths : 3,
      is_paid_project: args.isPaidProject !== false,
      allow_demo: args.allowDemo !== false,
      source: 'valores explícitos'
    };
  }

  const values = {
    code,
    name,
    description: 'DaleVentas POS — proyecto activo de Appyra (project mode).',
    is_active: true,
    monthly_price: billing.monthly_price,
    currency: billing.currency,
    demo_days: billing.demo_days,
    min_purchase_months: billing.min_purchase_months,
    is_paid_project: billing.is_paid_project,
    allow_demo: billing.allow_demo
  };

  const insertColumns = Object.keys(values).filter((column) => columns.has(column));

  console.log('\nConfiguración comercial a usar (origen: ' + billing.source + '):');
  for (const column of insertColumns) {
    console.log(`  ${column}: ${values[column]}`);
  }
  console.log('\nNOTA: revisa el precio en la pantalla Proyectos antes de vender.');

  if (args.dryRun) {
    console.log('\n--dry-run: no se escribió nada.\n');
    return;
  }

  if (String(process.env.CONFIRM_SEED_DALEVENTAS || '').trim() !== '1') {
    console.log(
      '\nEscritura bloqueada. Vuelve a ejecutar con CONFIRM_SEED_DALEVENTAS=1 ' +
        '(y hazlo primero en un entorno seguro/local/UAT).\n'
    );
    process.exitCode = 2;
    return;
  }

  const placeholders = insertColumns.map((_, index) => `$${index + 1}`).join(', ');
  const insertRes = await pool.query(
    `INSERT INTO projects (${insertColumns.join(', ')})
     VALUES (${placeholders})
     RETURNING id, code, name, is_active, created_at`,
    insertColumns.map((column) => values[column])
  );

  const created = insertRes.rows[0];
  console.log('\nProyecto creado:');
  console.log(`  id: ${created.id}`);
  console.log(`  code: ${created.code}`);
  console.log(`  name: ${created.name}`);
  console.log(`  is_active: ${created.is_active}`);
  console.log(`  created_at: ${created.created_at}`);
  console.log('\nLa pantalla Proyectos mostrará únicamente este proyecto.\n');
}

main()
  .then(() => pool.end())
  .catch(async (error) => {
    console.error('\nError:', error.message);
    await pool.end();
    process.exitCode = 1;
  });
