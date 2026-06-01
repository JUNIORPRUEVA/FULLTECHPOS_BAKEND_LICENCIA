/**
 * Script para crear datos de prueba de licencia en producción.
 * 
 * Crea:
 * 1. Un proyecto FULLCREDIT si no existe
 * 2. Un customer de prueba
 * 3. Una licencia DEMO ya vencida (para probar el bloqueo)
 * 4. Una activación para el device_id del emulador
 * 
 * Uso:
 *   node backend/scripts/setupDemoVencido.js <DEVICE_ID>
 * 
 * Ejemplo:
 *   node backend/scripts/setupDemoVencido.js "emulador-test-12345"
 * 
 * Requiere:
 *   - Conexión a la DB de producción configurada en .env
 *   - Las migraciones 042 y 043 ejecutadas
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '..', '.env') });
const { pool } = require('../db/pool');
const { generateLicenseKey } = require('../utils/licenseKey');

const DEVICE_ID = process.argv[2] || `emulador-test-${Date.now()}`;

async function main() {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`  🛠️  CONFIGURANDO DATOS DE PRUEBA`);
  console.log(`  Device ID: ${DEVICE_ID}`);
  console.log(`${'='.repeat(60)}\n`);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Crear o actualizar proyecto FULLCREDIT
    console.log('📌 1. Creando/actualizando proyecto FULLCREDIT...');
    const projectRes = await client.query(
      `INSERT INTO projects (code, name, description, monthly_price, currency, demo_days, min_purchase_months, is_paid_project, allow_demo, is_active, created_at, updated_at)
       VALUES ('FULLCREDIT', 'FullCredit', 'Sistema de gestión de préstamos', 15.00, 'USD', 5, 3, true, true, true, NOW(), NOW())
       ON CONFLICT (code) DO UPDATE SET
         monthly_price = 15.00, currency = 'USD', demo_days = 5, min_purchase_months = 3,
         is_paid_project = true, allow_demo = true, is_active = true, updated_at = NOW()
       RETURNING id, code, name, monthly_price, demo_days, min_purchase_months`,
      []
    );
    const project = projectRes.rows[0];
    console.log(`  ✅ Proyecto: ${project.name} (${project.code})`);
    console.log(`     ID: ${project.id}`);
    console.log(`     Precio: USD ${project.monthly_price}/mes`);
    console.log(`     Demo: ${project.demo_days} días`);
    console.log(`     Mínimo: ${project.min_purchase_months} meses`);

    // 2. Crear customer de prueba
    console.log('\n📌 2. Creando customer de prueba...');
    const customerRes = await client.query(
      `INSERT INTO customers (nombre_negocio, contacto_nombre, contacto_email, contacto_telefono, created_at, updated_at)
       VALUES ('Mi Negocio Prueba', 'Juan Pérez', 'juan@test.com', '8095550101', NOW(), NOW())
       RETURNING id, nombre_negocio`,
      []
    );
    const customer = customerRes.rows[0];
    console.log(`  ✅ Customer: ${customer.nombre_negocio} (ID: ${customer.id})`);

    // 3. Verificar si ya existe demo para este device
    console.log('\n📌 3. Verificando si ya existe demo para este device...');
    const existingRes = await client.query(
      `SELECT l.id, l.license_key, l.tipo, l.estado, l.fecha_inicio, l.fecha_fin
       FROM licenses l
       JOIN license_activations a ON a.license_id = l.id
       WHERE a.device_id = $1 AND a.project_id = $2
       ORDER BY l.created_at DESC LIMIT 1`,
      [DEVICE_ID, project.id]
    );

    if (existingRes.rows.length > 0) {
      console.log(`  ⚠️  Ya existe una licencia para este device:`);
      console.log(`     Key: ${existingRes.rows[0].license_key}`);
      console.log(`     Tipo: ${existingRes.rows[0].tipo}`);
      console.log(`     Estado: ${existingRes.rows[0].estado}`);
      console.log(`     Inicio: ${existingRes.rows[0].fecha_inicio}`);
      console.log(`     Fin: ${existingRes.rows[0].fecha_fin}`);
      
      // Si es demo activa, la vencemos
      if (existingRes.rows[0].tipo === 'DEMO' && existingRes.rows[0].estado === 'ACTIVA') {
        console.log('\n📌 4. Venciendo demo existente...');
        const fechaVencida = new Date(Date.now() - 24 * 60 * 60 * 1000); // ayer
        await client.query(
          `UPDATE licenses SET fecha_fin = $2, estado = 'VENCIDA' WHERE id = $1`,
          [existingRes.rows[0].id, fechaVencida]
        );
        await client.query(
          `UPDATE license_activations SET estado = 'VENCIDA' WHERE license_id = $1 AND device_id = $2`,
          [existingRes.rows[0].id, DEVICE_ID]
        );
        console.log('  ✅ Demo vencida exitosamente');
      }
    } else {
      // 4. Crear demo ya vencida (para probar bloqueo)
      console.log('\n📌 4. Creando demo ya vencida...');
      const licenseKey = generateLicenseKey('DEMO');
      const fechaInicio = new Date(Date.now() - 10 * 24 * 60 * 60 * 1000); // hace 10 días
      const fechaFin = new Date(Date.now() - 5 * 24 * 60 * 60 * 1000); // venció hace 5 días

      const licRes = await client.query(
        `INSERT INTO licenses (project_id, customer_id, license_key, tipo, dias_validez, max_dispositivos, estado, fecha_inicio, fecha_fin, notas)
         VALUES ($1, $2, $3, 'DEMO', 5, 1, 'VENCIDA', $4, $5, 'Demo vencida - prueba de bloqueo')
         RETURNING id, license_key`,
        [project.id, customer.id, licenseKey, fechaInicio, fechaFin]
      );
      const license = licRes.rows[0];
      console.log(`  ✅ Demo creada: ${license.license_key}`);

      // 5. Crear activación
      await client.query(
        `INSERT INTO license_activations (license_id, project_id, device_id, estado)
         VALUES ($1, $2, $3, 'VENCIDA')`,
        [license.id, project.id, DEVICE_ID]
      );
      console.log('  ✅ Activación creada');

      // 6. Registrar demo trial
      try {
        await client.query(
          `INSERT INTO demo_trials (project_id, device_id, contacto_email_norm, customer_id, license_id)
           VALUES ($1, $2, 'juan@test.com', $3, $4)`,
          [project.id, DEVICE_ID, customer.id, license.id]
        );
        console.log('  ✅ Demo trial registrado');
      } catch (e) {
        if (e.code === '23505') {
          console.log('  ⚠️  Demo trial ya existe');
        } else {
          throw e;
        }
      }
    }

    await client.query('COMMIT');

    console.log(`\n${'='.repeat(60)}`);
    console.log(`  ✅ DATOS DE PRUEBA CONFIGURADOS`);
    console.log(`${'='.repeat(60)}`);
    console.log(`\n  Device ID: ${DEVICE_ID}`);
    console.log(`\n  Ahora puedes probar:`);
    console.log(`  1. POST /api/public/license/validate`);
    console.log(`     Payload: {"project_code":"FULLCREDIT","device_id":"${DEVICE_ID}"}`);
    console.log(`     → Debe responder con DEMO_EXPIRED`);
    console.log(`\n  2. GET /api/public/projects/FULLCREDIT/billing`);
    console.log(`     → Debe mostrar precios`);
    console.log(`\n  3. POST /api/public/license-payments/create-paypal-order`);
    console.log(`     Payload: {"project_code":"FULLCREDIT","device_id":"${DEVICE_ID}","months":3}`);
    console.log(`     → Debe crear orden PayPal`);
    console.log(`\n  Para probar con curl:`);
    console.log(`  curl -X POST ${process.env.APPYRA_API_URL || 'https://fullpos-backend-fullposlicenciaswed.onqyr1.easypanel.host'}/api/public/license/validate \\`);
    console.log(`    -H "Content-Type: application/json" \\`);
    console.log(`    -d '{"project_code":"FULLCREDIT","device_id":"${DEVICE_ID}"}'`);

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('\n❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  } finally {
    client.release();
  }
}

main();
