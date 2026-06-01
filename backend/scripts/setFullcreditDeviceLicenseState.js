/**
 * Script para forzar estados de licencia en un dispositivo FullCredit.
 * Útil para pruebas desde el emulador.
 * 
 * Uso:
 *   node backend/scripts/setFullcreditDeviceLicenseState.js DEVICE_ID NO_LICENSE
 *   node backend/scripts/setFullcreditDeviceLicenseState.js DEVICE_ID DEMO_ACTIVE
 *   node backend/scripts/setFullcreditDeviceLicenseState.js DEVICE_ID DEMO_EXPIRED
 *   node backend/scripts/setFullcreditDeviceLicenseState.js DEVICE_ID LICENSE_ACTIVE
 *   node backend/scripts/setFullcreditDeviceLicenseState.js DEVICE_ID LICENSE_EXPIRED
 *   node backend/scripts/setFullcreditDeviceLicenseState.js DEVICE_ID RESET
 */
const { pool } = require('../db/pool');

const DEVICE_ID = process.argv[2];
const STATE = (process.argv[3] || '').toUpperCase();

const VALID_STATES = ['NO_LICENSE', 'DEMO_ACTIVE', 'DEMO_EXPIRED', 'LICENSE_ACTIVE', 'LICENSE_EXPIRED', 'RESET'];

async function main() {
  if (!DEVICE_ID || !STATE) {
    console.log('Uso: node backend/scripts/setFullcreditDeviceLicenseState.js DEVICE_ID STATE');
    console.log('Estados:', VALID_STATES.join(', '));
    process.exit(1);
  }

  if (!VALID_STATES.includes(STATE)) {
    console.log(`Estado inválido: ${STATE}`);
    console.log('Estados válidos:', VALID_STATES.join(', '));
    process.exit(1);
  }

  console.log(`=== Forzando estado ${STATE} para device ${DEVICE_ID} ===\n`);

  // Obtener proyecto FULLCREDIT
  const projRes = await pool.query("SELECT id, code, demo_days FROM projects WHERE code = 'FULLCREDIT'");
  if (projRes.rows.length === 0) {
    console.log('ERROR: Proyecto FULLCREDIT no encontrado');
    process.exit(1);
  }
  const project = projRes.rows[0];
  console.log('Proyecto:', project.code, project.id);

  const now = new Date();
  const demoDays = Math.max(1, Number(project.demo_days) || 5);

  if (STATE === 'NO_LICENSE' || STATE === 'RESET') {
    // Eliminar todo rastro de este device
    console.log('\nEliminando activaciones para device...');
    const actRes = await pool.query(
      `DELETE FROM license_activations WHERE device_id = $1 RETURNING id`,
      [DEVICE_ID]
    );
    console.log(`  Activaciones eliminadas: ${actRes.rowCount}`);

    // Eliminar demo_trials
    try {
      const trialRes = await pool.query(
        `DELETE FROM demo_trials WHERE device_id = $1 RETURNING id`,
        [DEVICE_ID]
      );
      console.log(`  Demo trials eliminados: ${trialRes.rowCount}`);
    } catch (e) {
      if (e.code === '42P01') console.log('  demo_trials no existe');
      else throw e;
    }

    console.log('\n✅ Estado RESET/NO_LICENSE aplicado');
    await pool.end();
    return;
  }

  // Para los demás estados, necesitamos un customer
  let customerId;
  const custRes = await pool.query(
    `SELECT DISTINCT c.id
     FROM customers c
     JOIN licenses l ON l.customer_id = c.id
     JOIN license_activations la ON la.license_id = l.id AND la.device_id = $1
     LIMIT 1`,
    [DEVICE_ID]
  );


  if (custRes.rows.length > 0) {
    customerId = custRes.rows[0].id;
    console.log('\nCustomer existente:', customerId);
  } else {
    // Crear customer de prueba
    const newCustRes = await pool.query(
      `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_telefono, contacto_email)
       VALUES ($1, $2, $3, $4)
       RETURNING id`,
      [`Test ${STATE}`, 'Test', '8090000000', `test-${DEVICE_ID}@test.com`]
    );
    customerId = newCustRes.rows[0].id;
    console.log('\nCustomer creado:', customerId);
  }

  // Eliminar activaciones previas para este device
  await pool.query(
    `DELETE FROM license_activations WHERE device_id = $1`,
    [DEVICE_ID]
  );

  // Eliminar demo_trials previos
  try {
    await pool.query(`DELETE FROM demo_trials WHERE device_id = $1`, [DEVICE_ID]);
  } catch (e) {
    if (e.code !== '42P01') throw e;
  }

  if (STATE === 'DEMO_ACTIVE' || STATE === 'DEMO_EXPIRED') {
    const isExpired = STATE === 'DEMO_EXPIRED';
    const fechaInicio = new Date(now.getTime() - (isExpired ? (demoDays + 1) * 24 * 60 * 60 * 1000 : 0));
    const fechaFin = new Date(fechaInicio.getTime() + demoDays * 24 * 60 * 60 * 1000);

    console.log(`\nCreando licencia DEMO ${isExpired ? 'VENCIDA' : 'ACTIVA'}...`);
    console.log(`  fecha_inicio: ${fechaInicio.toISOString()}`);
    console.log(`  fecha_fin: ${fechaFin.toISOString()}`);

    const licRes = await pool.query(
      `INSERT INTO licenses (project_id, customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, fecha_inicio, fecha_fin, notas)
       VALUES ($1, $2, $3, 'DEMO', $4, 1, 'ACTIVA', $5::timestamp, $6::timestamp, $7)
       RETURNING id, license_key`,
      [project.id, customerId, `DEMO-TEST-${DEVICE_ID}-${Date.now()}`, demoDays, fechaInicio, fechaFin, `Test ${STATE}`]
    );
    const license = licRes.rows[0];
    console.log('  Licencia creada:', license.id, license.license_key);

    // Crear activación
    await pool.query(
      `INSERT INTO license_activations (license_id, project_id, device_id, estado)
       VALUES ($1, $2, $3, 'ACTIVA')`,
      [license.id, project.id, DEVICE_ID]
    );
    console.log('  Activación creada');

    // Registrar demo_trial
    try {
      await pool.query(
        `INSERT INTO demo_trials (project_id, device_id, customer_id, license_id)
         VALUES ($1, $2, $3, $4)`,
        [project.id, DEVICE_ID, customerId, license.id]
      );
      console.log('  Demo trial registrado');
    } catch (e) {
      if (e.code === '42P01') console.log('  demo_trials no existe, skip');
      else if (e.code === '23505') console.log('  demo_trial ya existe');
      else throw e;
    }

    console.log(`\n✅ Estado ${STATE} aplicado`);
  }

  if (STATE === 'LICENSE_ACTIVE' || STATE === 'LICENSE_EXPIRED') {
    const isExpired = STATE === 'LICENSE_EXPIRED';
    const months = 3;
    const fechaInicio = new Date(now.getTime() - (isExpired ? (months * 30 + 1) * 24 * 60 * 60 * 1000 : 0));
    const fechaFin = new Date(fechaInicio.getTime() + months * 30 * 24 * 60 * 60 * 1000);

    console.log(`\nCreando licencia FULL ${isExpired ? 'VENCIDA' : 'ACTIVA'}...`);
    console.log(`  fecha_inicio: ${fechaInicio.toISOString()}`);
    console.log(`  fecha_fin: ${fechaFin.toISOString()}`);

    const licRes = await pool.query(
      `INSERT INTO licenses (project_id, customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, fecha_inicio, fecha_fin, notas)
       VALUES ($1, $2, $3, 'FULL', $4, 1, 'ACTIVA', $5::timestamp, $6::timestamp, $7)
       RETURNING id, license_key`,
      [project.id, customerId, `FULL-TEST-${DEVICE_ID}-${Date.now()}`, months * 30, fechaInicio, fechaFin, `Test ${STATE}`]
    );
    const license = licRes.rows[0];
    console.log('  Licencia creada:', license.id, license.license_key);

    // Crear activación
    await pool.query(
      `INSERT INTO license_activations (license_id, project_id, device_id, estado)
       VALUES ($1, $2, $3, 'ACTIVA')`,
      [license.id, project.id, DEVICE_ID]
    );
    console.log('  Activación creada');

    console.log(`\n✅ Estado ${STATE} aplicado`);
  }

  await pool.end();
}

main().catch(err => {
  console.error('FATAL:', err);
  process.exit(1);
});
