const { pool } = require('../db/pool');

async function createCustomer({ nombre_negocio, contacto_nombre, contacto_telefono, contacto_email }) {
  const result = await pool.query(
    `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email)
     VALUES ($1, $2, $3, $4)
     RETURNING *`,
    [nombre_negocio, contacto_nombre || null, contacto_telefono || null, contacto_email || null]
  );
  return result.rows[0];
}

async function listCustomers({ limit, offset }) {
  const totalRes = await pool.query('SELECT COUNT(*)::int AS total FROM customers');
  const total = totalRes.rows[0]?.total || 0;

  const rowsRes = await pool.query(
    `SELECT *
     FROM customers
     ORDER BY created_at DESC
     LIMIT $1 OFFSET $2`,
    [limit, offset]
  );

  return { total, customers: rowsRes.rows };
}

async function getCustomerById(customerId) {
  const result = await pool.query('SELECT * FROM customers WHERE id = $1', [customerId]);
  return result.rows[0] || null;
}

module.exports = {
  createCustomer,
  listCustomers,
  getCustomerById
};
