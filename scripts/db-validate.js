/**
 * db-validate.js — Phase 6 database structure validation
 *
 * Checks that all required SaaS tables, columns, indexes, and seed data exist.
 * Exits 0 if all pass, 1 if any check fails.
 *
 * Usage:
 *   node scripts/db-validate.js
 *   DATABASE_URL=postgres://... node scripts/db-validate.js
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

let PASSED = 0;
let FAILED = 0;

function pass(label) {
  PASSED++;
  process.stdout.write(`  ✓ ${label}\n`);
}

function fail(label, detail = '') {
  FAILED++;
  process.stdout.write(`  ✗ ${label}${detail ? '  ← ' + detail : ''}\n`);
}

async function checkTables() {
  console.log('\n[1] Required tables');
  const required = [
    'companies',
    'licenses',
    'license_activations',
    'customers',
    'projects',
    'product_plans',
    'company_subscriptions',
    'subscription_payments',
    'audit_logs',
    'platform_users',
    'roles',
    'permissions',
    'platform_user_roles',
    'admin_sessions'
  ];

  const res = await pool.query(
    `SELECT tablename FROM pg_tables WHERE schemaname = 'public'`
  );
  const existing = new Set(res.rows.map(r => r.tablename));

  for (const t of required) {
    if (existing.has(t)) pass(`table '${t}' exists`);
    else fail(`table '${t}' MISSING`);
  }
}

async function checkColumns() {
  console.log('\n[2] Required columns on key tables');
  const checks = [
    // licenses SaaS fields (migration 030)
    ['licenses', 'subscription_id'],
    ['licenses', 'company_id'],
    ['licenses', 'product_id'],
    ['licenses', 'metadata'],
    ['licenses', 'issued_at'],
    // company_subscriptions
    ['company_subscriptions', 'status'],
    ['company_subscriptions', 'end_date'],
    ['company_subscriptions', 'grace_until'],
    ['company_subscriptions', 'cancelled_at'],
    ['company_subscriptions', 'suspended_at'],
    ['company_subscriptions', 'metadata'],
    // subscription_payments
    ['subscription_payments', 'status'],
    ['subscription_payments', 'amount'],
    ['subscription_payments', 'paid_at'],
    // audit_logs
    ['audit_logs', 'action'],
    ['audit_logs', 'target_type'],
    ['audit_logs', 'before_data'],
    ['audit_logs', 'after_data'],
    // product_plans
    ['product_plans', 'billing_period'],
    ['product_plans', 'price_amount'],
    ['product_plans', 'default_grace_days'],
  ];

  const res = await pool.query(
    `SELECT table_name, column_name
     FROM information_schema.columns
     WHERE table_schema = 'public'`
  );
  const existing = new Set(res.rows.map(r => `${r.table_name}.${r.column_name}`));

  for (const [table, col] of checks) {
    const key = `${table}.${col}`;
    if (existing.has(key)) pass(`column ${key}`);
    else fail(`column ${key} MISSING`);
  }
}

async function checkIndexes() {
  console.log('\n[3] Key indexes');
  const required = [
    'idx_company_subscriptions_status',
    'idx_company_subscriptions_end_date',
    'idx_company_subscriptions_company_id',
    'idx_subscription_payments_status',
    'idx_subscription_payments_paid_at',
    'idx_audit_logs_action',
    'idx_audit_logs_created_at',
  ];

  const res = await pool.query(
    `SELECT indexname FROM pg_indexes WHERE schemaname = 'public'`
  );
  const existing = new Set(res.rows.map(r => r.indexname));

  for (const idx of required) {
    if (existing.has(idx)) pass(`index '${idx}'`);
    else fail(`index '${idx}' MISSING`);
  }
}

async function checkSeeds() {
  console.log('\n[4] Seed data');

  // Roles
  const rolesRes = await pool.query(`SELECT COUNT(*)::int AS cnt FROM roles`);
  const roleCount = rolesRes.rows[0]?.cnt || 0;
  if (roleCount >= 3) pass(`roles seeded (${roleCount} rows)`);
  else fail(`roles table has only ${roleCount} rows — expected >= 3`);

  // Permissions
  const permRes = await pool.query(`SELECT COUNT(*)::int AS cnt FROM permissions`);
  const permCount = permRes.rows[0]?.cnt || 0;
  if (permCount >= 5) pass(`permissions seeded (${permCount} rows)`);
  else fail(`permissions table has only ${permCount} rows — expected >= 5`);

  // Default project
  const projRes = await pool.query(`SELECT COUNT(*)::int AS cnt FROM projects`);
  const projCount = projRes.rows[0]?.cnt || 0;
  if (projCount >= 1) pass(`projects seeded (${projCount} rows)`);
  else fail(`projects table is empty — expected >= 1 (default project)`);

  // Product plans (default plans seeded in migration 032)
  const planRes = await pool.query(`SELECT COUNT(*)::int AS cnt FROM product_plans`);
  const planCount = planRes.rows[0]?.cnt || 0;
  if (planCount >= 1) pass(`product_plans seeded (${planCount} rows)`);
  else fail(`product_plans empty — run migration 032`);
}

async function checkConstraints() {
  console.log('\n[5] Critical check constraints');
  const checks = [
    ['company_subscriptions', 'ck_company_subscriptions_status'],
    ['audit_logs', 'ck_audit_logs_target_type'],
    ['audit_logs', 'ck_audit_logs_actor_type'],
    ['subscription_payments', 'ck_subscription_payments_status'],
    ['subscription_payments', 'ck_subscription_payments_amount'],
  ];

  const res = await pool.query(
    `SELECT conname, conrelid::regclass::text AS table_name
     FROM pg_constraint
     WHERE contype = 'c'`
  );
  const existing = new Set(res.rows.map(r => r.conname));

  for (const [, constraintName] of checks) {
    if (existing.has(constraintName)) pass(`constraint '${constraintName}'`);
    else fail(`constraint '${constraintName}' MISSING`);
  }
}

async function checkFKs() {
  console.log('\n[6] Foreign key integrity spot-check');
  const checks = [
    {
      label: 'No company_subscriptions with orphan company_id',
      sql: `SELECT COUNT(*)::int AS cnt FROM company_subscriptions cs
            WHERE NOT EXISTS (SELECT 1 FROM companies c WHERE c.id = cs.company_id)`
    },
    {
      label: 'No subscription_payments with orphan subscription_id',
      sql: `SELECT COUNT(*)::int AS cnt FROM subscription_payments sp
            WHERE NOT EXISTS (SELECT 1 FROM company_subscriptions cs WHERE cs.id = sp.subscription_id)`
    },
    {
      label: 'No licenses with invalid subscription_id',
      sql: `SELECT COUNT(*)::int AS cnt FROM licenses l
            WHERE l.subscription_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM company_subscriptions cs WHERE cs.id = l.subscription_id)`
    }
  ];

  for (const { label, sql } of checks) {
    const r = await pool.query(sql);
    const cnt = r.rows[0]?.cnt || 0;
    if (cnt === 0) pass(label);
    else fail(label, `${cnt} orphan rows found`);
  }
}

async function checkProductPlanColumns() {
  console.log('\n[7] product_plans column name check (grace_days vs default_grace_days)');
  // Migration may use either name; detect what's actually there.
  const res = await pool.query(
    `SELECT column_name FROM information_schema.columns
     WHERE table_schema='public' AND table_name='product_plans'`
  );
  const cols = new Set(res.rows.map(r => r.column_name));
  const hasGrace = cols.has('grace_days') || cols.has('default_grace_days');
  if (hasGrace) pass('product_plans has a grace_days column');
  else fail('product_plans missing grace_days / default_grace_days column');
}

// ─── main ─────────────────────────────────────────────────────────────────────

(async () => {
  console.log('='.repeat(60));
  console.log('  DB VALIDATION — SaaS Manager Phase 1-5');
  console.log(`  DB: ${(connectionString || '(env PG vars)').replace(/:([^@]+)@/, ':***@')}`);
  console.log('='.repeat(60));

  try {
    await pool.query('SELECT 1');
    pass('DB connection successful');
  } catch (e) {
    fail('DB connection FAILED', e.message);
    process.exitCode = 1;
    await pool.end();
    return;
  }

  await checkTables();
  await checkColumns();
  await checkIndexes();
  await checkSeeds();
  await checkConstraints();
  await checkFKs();
  await checkProductPlanColumns();

  console.log('\n' + '='.repeat(60));
  console.log(`  RESULTS: ${PASSED} passed, ${FAILED} failed`);
  console.log('='.repeat(60));

  await pool.end();
  process.exitCode = FAILED > 0 ? 1 : 0;
})();
