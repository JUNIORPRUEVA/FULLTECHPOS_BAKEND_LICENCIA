require('dotenv').config({ path: '.env' });

const { pool } = require('../backend/db/pool');

async function main() {
  try {
    await pool.query('BEGIN');

    const sql =
      'INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email) ' +
      'VALUES ($1, $2, $3, $4) RETURNING id';

    const values = ['TEST_DEBUG', null, '8090000000', null];
    const r = await pool.query(sql, values);

    console.log('insert ok id=', r.rows[0]?.id);
    await pool.query('ROLLBACK');
  } catch (e) {
    console.error('insert failed');
    console.error({
      code: e?.code,
      message: e?.message,
      detail: e?.detail,
      hint: e?.hint,
      where: e?.where,
      constraint: e?.constraint,
      table: e?.table,
      column: e?.column
    });
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

main();
