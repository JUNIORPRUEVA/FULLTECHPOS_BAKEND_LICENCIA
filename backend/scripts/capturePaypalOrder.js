/**
 * capturePaypalOrder.js
 * Captura una orden de PayPal aprobada y activa/renueva la licencia.
 * 
 * Uso: node backend/scripts/capturePaypalOrder.js <payment_order_id> <paypal_order_id>
 * 
 * Ejemplo:
 *   node backend/scripts/capturePaypalOrder.js UUID_PAYMENT_ORDER UUID_PAYPAL_ORDER
 * 
 * Requisitos:
 * - .env con PAYPAL_CLIENT_ID y PAYPAL_CLIENT_SECRET
 * - La orden debe haber sido aprobada en PayPal (pagada con sandbox buyer)
 */
require('dotenv').config();
const { pool } = require('../db/pool');
const licensePaymentOrdersModel = require('../models/licensePaymentOrdersModel');
const licensesModel = require('../models/licensesModel');
const paypalService = require('../services/paypalService');

async function captureOrder(paymentOrderId, paypalOrderId) {
  console.log('========================================');
  console.log('  CAPTURAR ORDEN PAYPAL');
  console.log('========================================\n');

  // Verificar credenciales
  const clientId = String(process.env.PAYPAL_CLIENT_ID || '').trim();
  const clientSecret = String(process.env.PAYPAL_CLIENT_SECRET || process.env.PAYPAL_SECRET || '').trim();
  
  if (!clientId || !clientSecret) {
    console.log('❌ PAYPAL_CLIENT_ID y PAYPAL_CLIENT_SECRET no están configurados.');
    process.exit(1);
  }

  try {
    // 1. Buscar orden local
    console.log('--- 1. Buscar orden local ---');
    let localOrder = null;
    if (paymentOrderId) {
      localOrder = await licensePaymentOrdersModel.getPaymentOrderById(paymentOrderId);
    } else if (paypalOrderId) {
      localOrder = await licensePaymentOrdersModel.getPaymentOrderByProviderOrderId(paypalOrderId);
    }

    if (!localOrder) {
      console.log('❌ Orden de pago no encontrada');
      process.exit(1);
    }

    console.log(`✅ Orden encontrada:`);
    console.log(`   ID: ${localOrder.id}`);
    console.log(`   Status: ${localOrder.status}`);
    console.log(`   Total: ${localOrder.total_amount} ${localOrder.currency}`);
    console.log(`   PayPal Order ID: ${localOrder.provider_order_id}`);
    console.log('');

    // 2. Verificar que no esté ya pagada
    if (String(localOrder.status).toUpperCase() === 'PAID') {
      console.log('⚠️  Esta orden ya fue pagada y procesada.');
      console.log(`   Paid at: ${localOrder.paid_at}`);
      console.log(`   Capture ID: ${localOrder.provider_capture_id}`);
      process.exit(0);
    }

    // 3. Capturar en PayPal
    console.log('--- 2. Capturar orden en PayPal ---');
    let captureResult;
    try {
      captureResult = await paypalService.captureOrder(localOrder.provider_order_id);
    } catch (paypalError) {
      console.log(`❌ Error al capturar: ${paypalError.message}`);
      await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
        status: 'FAILED',
        raw_response: { error: paypalError.message, step: 'capture' },
      });
      console.log('   Orden marcada como FAILED');
      process.exit(1);
    }

    console.log(`✅ Captura realizada:`);
    console.log(`   Status PayPal: ${captureResult.status}`);
    console.log(`   Capture ID: ${captureResult.capture_id}`);
    console.log(`   Payer: ${captureResult.payer_email}`);
    console.log(`   Amount: ${captureResult.amount} ${captureResult.currency}`);
    console.log('');

    // 4. Verificar COMPLETED
    if (String(captureResult.status).toUpperCase() !== 'COMPLETED') {
      console.log(`❌ El pago no fue completado. Estado: ${captureResult.status}`);
      await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
        status: 'FAILED',
        raw_response: { captureResult, error: `PayPal status: ${captureResult.status}` },
      });
      process.exit(1);
    }

    // 5. Actualizar orden local como PAID
    console.log('--- 3. Actualizar orden local como PAID ---');
    const updatedOrder = await licensePaymentOrdersModel.capturePaymentOrder(localOrder.id, {
      provider_capture_id: captureResult.capture_id,
      status: 'PAID',
      raw_response: captureResult.raw || captureResult,
      paid_at: new Date(),
    });
    console.log(`✅ Orden actualizada: ${updatedOrder.status}`);
    console.log(`   Paid at: ${updatedOrder.paid_at}`);
    console.log('');

    // 6. Activar o extender licencia
    console.log('--- 4. Activar/extender licencia ---');
    let license;
    try {
      license = await licensesModel.activateOrExtendPaidLicense({
        customerId: localOrder.customer_id,
        projectId: localOrder.project_id,
        months: localOrder.months,
        paymentOrderId: localOrder.id,
        maxDevices: 1,
      });
    } catch (licenseError) {
      console.log(`❌ Error al activar licencia: ${licenseError.message}`);
      console.log('   El pago fue capturado pero la licencia no se pudo activar.');
      console.log('   Contacte a soporte.');
      process.exit(1);
    }

    console.log(`✅ Licencia activada/renovada:`);
    console.log(`   ID: ${license.id}`);
    console.log(`   License Key: ${license.license_key}`);
    console.log(`   Estado: ${license.estado}`);
    console.log(`   Fecha inicio: ${license.fecha_inicio}`);
    console.log(`   Fecha fin: ${license.fecha_fin}`);
    console.log(`   Activation source: ${license.activation_source}`);
    console.log(`   Payment order ID: ${license.payment_order_id}`);
    console.log('');

    console.log('========================================');
    console.log('  ✅ PAGO COMPLETADO Y LICENCIA ACTIVADA');
    console.log('========================================');
    console.log('');
    console.log(`📋 Resumen final:`);
    console.log(`   Payment Order ID: ${localOrder.id}`);
    console.log(`   PayPal Order ID: ${localOrder.provider_order_id}`);
    console.log(`   Capture ID: ${captureResult.capture_id}`);
    console.log(`   Total: ${localOrder.total_amount} ${localOrder.currency}`);
    console.log(`   Meses: ${localOrder.months}`);
    console.log(`   Licencia: ${license.license_key}`);
    console.log(`   Estado: ${license.estado}`);
    console.log(`   Expira: ${license.fecha_fin}`);

    await pool.end();
  } catch (error) {
    console.error('Error:', error);
    await pool.end();
    process.exit(1);
  }
}

// Parsear argumentos
const args = process.argv.slice(2);
const paymentOrderId = args[0];
const paypalOrderId = args[1];

if (!paymentOrderId && !paypalOrderId) {
  console.log('Uso: node backend/scripts/capturePaypalOrder.js <payment_order_id> <paypal_order_id>');
  console.log('');
  console.log('Ejemplo:');
  console.log('  node backend/scripts/capturePaypalOrder.js UUID_PAYMENT_ORDER UUID_PAYPAL_ORDER');
  process.exit(1);
}

captureOrder(paymentOrderId, paypalOrderId);
