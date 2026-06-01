/**
 * Script de diagnóstico de configuración PayPal.
 * 
 * Uso:
 *   node backend/scripts/diagnosePaypalConfig.js
 * 
 * Opciones:
 *   --test-order   Crea una orden de prueba de USD 1.00 para verificar el flujo completo
 * 
 * Este script:
 * 1. Lee y valida la configuración PayPal desde variables de entorno
 * 2. Prueba obtener un access token
 * 3. Opcionalmente crea una orden de prueba
 * 
 * NUNCA imprime el client secret.
 */

// Cargar .env desde la raíz del proyecto
const path = require('path');
const rootDir = path.join(__dirname, '..');
require('dotenv').config({ path: path.join(rootDir, '.env') });

const paypalService = require('../services/paypalService');

async function main() {
  console.log('\n========================================');
  console.log('  DIAGNÓSTICO DE CONFIGURACIÓN PAYPAL');
  console.log('========================================\n');

  // 1. Validar configuración
  console.log('📋 Validando configuración...');
  const config = paypalService.validatePaypalConfig();

  console.log(`  Modo:              ${config.mode}`);
  console.log(`  Base URL:          ${config.baseUrl}`);
  console.log(`  Client ID config:  ${config.clientIdConfigured ? '✅ Sí' : '❌ No'}`);
  console.log(`  Client Secret:     ${config.clientSecretConfigured ? '✅ Configurado' : '❌ No configurado'}`);
  console.log(`  Return URL:        ${config.returnUrl || '❌ No configurada'}`);
  console.log(`  Cancel URL:        ${config.cancelUrl || '❌ No configurada'}`);
  console.log(`  Webhook ID:        ${config.webhookIdConfigured ? '✅ Configurado' : '⚠️  No configurado'}`);
  console.log(`  Brand Name:        ${config.brandName}`);

  if (!config.ok) {
    console.log(`\n❌ Configuración incompleta. Faltan:`);
    config.missing.forEach(v => console.log(`   - ${v}`));
    console.log('\n⚠️  No se puede continuar con las pruebas. Corrige las variables faltantes.');
    process.exit(1);
  }

  console.log('\n✅ Configuración válida.\n');

  // 2. Probar access token
  console.log('🔑 Probando obtención de access token...');
  try {
    const token = await paypalService.getAccessToken();
    console.log(`  ✅ Access token obtenido: ${token.slice(0, 20)}...${token.slice(-10)}`);
  } catch (error) {
    console.log(`  ❌ Error: ${error.message}`);
    console.log('\n⚠️  No se puede continuar. Verifica las credenciales PayPal.');
    process.exit(1);
  }

  // 3. Probar crear orden (opcional)
  const shouldTestOrder = process.argv.includes('--test-order');
  if (shouldTestOrder) {
    console.log('\n🛒 Creando orden de prueba (USD 1.00)...');
    try {
      const order = await paypalService.createOrder({
        amount: 1.00,
        currency: 'USD',
        description: 'Orden de prueba - Diagnóstico PayPal',
        metadata: {
          invoice_id: `DIAG-${Date.now()}`,
        },
      });

      console.log(`  ✅ Orden creada:`);
      console.log(`     ID:            ${order.id}`);
      console.log(`     Status:        ${order.status}`);
      console.log(`     Checkout URL:  ${order.checkout_url}`);
      console.log(`\n🔗 Abre esta URL en el navegador para probar el flujo de pago:`);
      console.log(`   ${order.checkout_url}`);
      console.log(`\n⚠️  Esta orden NO fue capturada. Si la pagas, quedará pendiente.`);
      console.log(`   Puedes capturarla manualmente con:`);
      console.log(`   node backend/scripts/capturePaypalOrder.js ${order.id}`);
    } catch (error) {
      console.log(`  ❌ Error al crear orden: ${error.message}`);
    }
  } else {
    console.log('\n💡 Para probar la creación de una orden, ejecuta:');
    console.log(`   node ${process.argv[1]} --test-order`);
  }

  console.log('\n========================================');
  console.log('  DIAGNÓSTICO COMPLETADO');
  console.log('========================================\n');
}

main().catch(error => {
  console.error('\n❌ Error inesperado:', error.message);
  process.exit(1);
});
