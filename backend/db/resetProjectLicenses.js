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

function parseArgs(argv) {
  const args = argv.slice(2);
  const cmd = args[0] || 'preview';

  let projectCode = 'FULLPOS';
  let yes = false;

  for (let i = 1; i < args.length; i++) {
    const a = args[i];
    if (a === '--project' || a === '--project_code') {
      projectCode = String(args[i + 1] || '').trim();
      i++;
      continue;
    }
    if (a === '--yes') {
      yes = true;
      continue;
    }
  }

  return { cmd, projectCode, yes };
}

async function getProjectByCode(client, code) {
  const res = await client.query('SELECT * FROM projects WHERE upper(code) = upper($1) LIMIT 1', [code]);
  return res.rows[0] || null;
}

async function preview(client, projectId) {
  const licCount = await client.query('SELECT COUNT(*)::int AS n FROM licenses WHERE project_id = $1', [projectId]);
  const actCount = await client.query(
    `SELECT COUNT(*)::int AS n
     FROM license_activations a
     JOIN licenses l ON l.id = a.license_id
     WHERE l.project_id = $1`,
    [projectId]
  );

  return {
    licenses: licCount.rows[0]?.n || 0,
    activations: actCount.rows[0]?.n || 0
  };
}

async function reset(client, projectId) {
  // ON DELETE CASCADE should remove license_activations, but we explicitly delete activations first
  // in case schema differs.
  await client.query(
    `DELETE FROM license_activations
     WHERE license_id IN (SELECT id FROM licenses WHERE project_id = $1)`,
    [projectId]
  );

  const deletedLic = await client.query('DELETE FROM licenses WHERE project_id = $1 RETURNING id', [projectId]);
  return { deleted_licenses: deletedLic.rowCount || 0 };
}

async function main() {
  const { cmd, projectCode, yes } = parseArgs(process.argv);
  const code = String(projectCode || 'FULLPOS').trim().toUpperCase();

  const client = await pool.connect();
  try {
    const project = await getProjectByCode(client, code);
    if (!project) {
      console.log(`❌ Proyecto no encontrado: ${code}`);
      process.exitCode = 1;
      return;
    }

    if (cmd === 'preview') {
      const info = await preview(client, project.id);
      console.log(JSON.stringify({ ok: true, project: { id: project.id, code: project.code }, ...info }, null, 2));
      return;
    }

    if (cmd === 'reset') {
      const info = await preview(client, project.id);
      console.log('About to delete licenses for project:', code);
      console.log(JSON.stringify(info, null, 2));

      if (!yes) {
        console.log('Dry-run. Re-run with: reset --project FULLPOS --yes');
        return;
      }

      await client.query('BEGIN');
      const result = await reset(client, project.id);
      await client.query('COMMIT');

      const after = await preview(client, project.id);
      console.log(JSON.stringify({ ok: true, deleted: result, after }, null, 2));
      return;
    }

    console.log('Usage: node backend/db/resetProjectLicenses.js preview|reset --project FULLPOS [--yes]');
    process.exitCode = 1;
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch {}
    console.error('❌ resetProjectLicenses error:', e?.code || e?.message || e);
    console.error(e);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
