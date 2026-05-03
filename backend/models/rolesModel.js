const { pool } = require('../db/pool');

async function listRoles() {
  const res = await pool.query('SELECT * FROM roles ORDER BY scope_type ASC, code ASC');
  return res.rows;
}

async function getRoleById(id, { client = pool } = {}) {
  const res = await client.query('SELECT * FROM roles WHERE id = $1', [id]);
  return res.rows[0] || null;
}

async function listPermissions() {
  const res = await pool.query('SELECT * FROM permissions ORDER BY resource ASC, action ASC, code ASC');
  return res.rows;
}

module.exports = {
  listRoles,
  getRoleById,
  listPermissions
};