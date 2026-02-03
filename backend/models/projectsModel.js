const { pool } = require('../db/pool');

function normalizeCode(code) {
  return String(code || '').trim().toUpperCase();
}

async function getProjectById(projectId) {
  const res = await pool.query('SELECT * FROM projects WHERE id = $1', [projectId]);
  return res.rows[0] || null;
}

async function getProjectByCode(code) {
  const c = normalizeCode(code);
  const res = await pool.query('SELECT * FROM projects WHERE code = $1', [c]);
  return res.rows[0] || null;
}

async function getDefaultProject() {
  return getProjectByCode('DEFAULT');
}

async function createProject({ code, name, description }) {
  const c = normalizeCode(code);
  const n = String(name || '').trim();
  const d = description == null ? null : String(description);

  const res = await pool.query(
    `INSERT INTO projects (code, name, description, is_active)
     VALUES ($1, $2, $3, true)
     RETURNING *`,
    [c, n, d]
  );
  return res.rows[0] || null;
}

async function listProjects() {
  const res = await pool.query(
    `SELECT *
     FROM projects
     ORDER BY created_at DESC`
  );
  return res.rows;
}

module.exports = {
  normalizeCode,
  getProjectById,
  getProjectByCode,
  getDefaultProject,
  createProject,
  listProjects
};
