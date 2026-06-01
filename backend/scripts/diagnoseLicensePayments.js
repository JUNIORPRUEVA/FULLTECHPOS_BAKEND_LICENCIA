/**
 * diagnoseLicensePayments.js
 * Script de diagnóstico para verificar la estructura de la base de datos
 * relacionada con el sistema de pagos de licencias.
 * 
 * Uso: node backend/scripts/diagnoseLicensePayments.js
 */
const { pool } = require('../db/pool');

async function diagnose() {
  console.log('========================================');
  console.log('  DIAGNÓSTICO - SISTEMA DE PAGOS');
  console.log('========================================\n');

  try {
    // 1. Columnas de projects
    console.log('--- 1. COLUMNAS DE projects ---');
    const projectsCols = await pool.query(
      `SELECT column_name, data_type, is_nullable, column_default
       FROM information_schema.columns
       WHERE table_name = 'projects'
       ORDER BY ordinal_position`
    );
    console.table(projectsCols.rows);
  } catch (e) {
    console.log('ERROR:', e.message);
  }

  try {
    // 2. Columnas de licenses
    console.log('\n--- 2. COLUMNAS DE licenses ---');
    const licensesCols = await pool.query(
      `SELECT column_name, data_type, is_nullable, column_default
       FROM information_schema.columns
       WHERE table_name = 'licenses'
       ORDER BY ordinal_position`
    );
    console.table(licensesCols.rows);
  } catch (e) {
    console.log('ERROR:', e.message);
  }

  try {
    // 3. Columnas de license_payment_orders
    console.log('\n--- 3. COLUMNAS DE license_payment_orders ---');
    const lpoCols = await pool.query(
      `SELECT column_name, data_type, is_nullable, column_default
       FROM information_schema.columns
       WHERE table_name = 'license_payment_orders'
       ORDER BY ordinal_position`
    );
    console.table(lpoCols.rows);
  } catch (e) {
    console.log('ERROR:', e.message);
  }

  try {
    // 4. Proyecto FULLPOS
    console.log('\n--- 4. PROYECTO FULLPOS ---');
    const fullpos = await pool.query(
      `SELECT id, code, name, monthly_price, currency, demo_days, 
              min_purchase_months, is_paid_project, allow_demo, is_active
       FROM projects
       WHERE code = 'FULLPOS'`
    );
    if (fullpos.rows.length === 0) {
      console.log('⚠️  No se encontró el proyecto FULLPOS');
    } else {
      console.table(fullpos.rows);
    }
  } catch (e) {
    console.log('ERROR:', e.message);
  }

  try {
    // 5. Últimas licencias
    console.log('\n--- 5. ÚLTIMAS 10 LICENCIAS ---');
    const licenses = await pool.query(
      `SELECT id, license_key, customer_id, project_id, estado, 
              activation_source, payment_order_id, 
              fecha_inicio AS activated_at, fecha_fin AS expires_at
       FROM licenses
       ORDER BY created_at DESC
       LIMIT 10`
    );
    console.table(licenses.rows);
  } catch (e) {
    console.log('ERROR:', e.message);
  }

  try {
    // 6. Últimas órdenes de pago
    console.log('\n--- 6. ÚLTIMAS 10 ÓRDENES DE PAGO ---');
    const orders = await pool.query(
      `SELECT id, customer_id, project_id, months, total_amount, 
              currency, status, provider_order_id, paid_at
       FROM license_payment_orders
       ORDER BY created_at DESC
       LIMIT 10`
    );
    console.table(orders.rows);
  } catch (e) {
    console.log('ERROR:', e.message);
  }

  try {
    // 7. Columnas de customers
    console.log('\n--- 7. COLUMNAS DE customers ---');
    const custCols = await pool.query(
      `SELECT column_name, data_type, is_nullable
       FROM information_schema.columns
       WHERE table_name = 'customers'
       ORDER BY ordinal_position`
    );
    console.table(custCols.rows);
  } catch (e) {
    console.log('ERROR:', e.message);
  }

  console.log('\n========================================');
  console.log('  DIAGNÓSTICO COMPLETADO');
  console.log('========================================');

  await pool.end();
}

diagnose().catch(e => {
  console.error('Error fatal:', e);
  process.exit(1);
});
