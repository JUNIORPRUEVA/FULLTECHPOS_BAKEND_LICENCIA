/**
 * projects-audit-readonly.js — Auditoría READ-ONLY de la tabla `projects`.
 *
 * Reporta todos los proyectos con su clasificación para project mode:
 *   - VISIBLE              → aparece en la pantalla Proyectos.
 *   - HIDDEN_LEGACY_PROJECT → preservado en DB/código, oculto en project mode.
 *
 * NUNCA escribe: solo ejecuta SELECT.
 *
 * Uso:
 *   node scripts/projects-audit-readonly.js
 *   DATABASE_URL=postgres://... node scripts/projects-audit-readonly.js
 *
 * Ejecútalo primero en un entorno seguro/local/UAT antes de tocar producción.
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

// Espejo de `frontend_flutter/lib/core/config/appyra_projects.dart`.
// Si cambia el registro central, actualiza también estas listas.
const VISIBLE_CODES = ['DALEVENTAS'];
const LEGACY_CODES = ['DEFAULT', 'FULLPOS', 'FULLCREDIT'];

function normalizeCode(code) {
  return String(code || '').trim().toUpperCase();
}

function classify(code) {
  const normalized = normalizeCode(code);
  if (VISIBLE_CODES.includes(normalized)) return 'VISIBLE (project mode)';
  if (LEGACY_CODES.includes(normalized)) return 'HIDDEN_LEGACY_PROJECT';
  return 'HIDDEN_LEGACY_PROJECT (no registrado en project mode)';
}

function fmt(value) {
  if (value === null || value === undefined) return '—';
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

async function tableExists(name) {
  const res = await pool.query('SELECT to_regclass($1) AS reg', [`public.${name}`]);
  return Boolean(res.rows[0] && res.rows[0].reg);
}

async function main() {
  console.log('\n=== APPYRA — AUDITORÍA READ-ONLY DE PROJECTS ===\n');

  const projectsRes = await pool.query(
    `SELECT id, code, name, description, is_active, created_at, updated_at
     FROM projects
     ORDER BY created_at ASC NULLS FIRST, code ASC`
  );

  console.log(`PROJECTS EN LA TABLA: ${projectsRes.rowCount}\n`);

  // Relaciones que apuntan a projects (project_id) — se detectan dinámicamente.
  const relationsRes = await pool.query(
    `SELECT table_name
     FROM information_schema.columns
     WHERE table_schema = 'public' AND column_name = 'project_id'
     ORDER BY table_name`
  );
  const relationTables = relationsRes.rows
    .map((row) => row.table_name)
    .filter((name) => name !== 'projects');

  const counts = new Map();
  for (const table of relationTables) {
    try {
      const res = await pool.query(
        `SELECT project_id, COUNT(*)::int AS total
         FROM ${table}
         WHERE project_id IS NOT NULL
         GROUP BY project_id`
      );
      for (const row of res.rows) {
        if (!counts.has(row.project_id)) counts.set(row.project_id, []);
        counts.get(row.project_id).push(`${table}=${row.total}`);
      }
    } catch (error) {
      console.log(`  (no se pudo contar ${table}: ${error.message})`);
    }
  }

  const hasProfileColumn = (
    await pool.query(
      `SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='projects' AND column_name='product_profile'`
    )
  ).rowCount > 0;

  for (const project of projectsRes.rows) {
    const profile = hasProfileColumn
      ? await pool.query('SELECT product_profile FROM projects WHERE id = $1', [project.id])
      : { rows: [{ product_profile: null }] };
    const profileValue = profile.rows[0] ? profile.rows[0].product_profile : null;

    console.log('-'.repeat(70));
    console.log(`id:    ${fmt(project.id)}`);
    console.log(`code:  ${fmt(project.code)}`);
    console.log(`name:  ${fmt(project.name)}`);
    console.log(`active: ${fmt(project.is_active)}`);
    console.log(`classification: ${classify(project.code)}`);
    console.log(`created_at: ${fmt(project.created_at)}`);
    console.log(`updated_at: ${fmt(project.updated_at)}`);
    console.log(
      `product_profile: ${
        profileValue ? 'sí (configurado)' : 'vacío'
      }`
    );
    console.log(`relations: ${(counts.get(project.id) || []).join(', ') || 'ninguna'}`);
  }

  const visible = projectsRes.rows.filter((p) => VISIBLE_CODES.includes(normalizeCode(p.code)));
  const hidden = projectsRes.rows.filter((p) => !VISIBLE_CODES.includes(normalizeCode(p.code)));

  console.log('-'.repeat(70));
  console.log(`\nRESUMEN`);
  console.log(`  VISIBLE EN PROJECT MODE: ${visible.length}`);
  console.log(`  OCULTOS (HIDDEN_LEGACY_PROJECT): ${hidden.length}`);
  if (visible.length === 0) {
    console.log(
      '\n  → No existe todavía un proyecto con code DALEVENTAS.' +
        '\n    Provisiona con: node scripts/seed-daleventas-project.js --billing-from=<CODE>'
    );
  }

  // Tablas auxiliares relevantes para DaleVentas (solo conteo informativo).
  for (const table of ['daleventas_commercial_plans', 'daleventas_commercial_profiles']) {
    if (await tableExists(table)) {
      const res = await pool.query(`SELECT COUNT(*)::int AS total FROM ${table}`);
      console.log(`  ${table}: ${res.rows[0].total} registros (sin modificar)`);
    }
  }

  console.log('\nAuditoría completada. No se escribió ningún dato.\n');
}

main()
  .then(() => pool.end())
  .catch(async (error) => {
    console.error('\nError en la auditoría:', error.message);
    await pool.end();
    process.exitCode = 1;
  });
