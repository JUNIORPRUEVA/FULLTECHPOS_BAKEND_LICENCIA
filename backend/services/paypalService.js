/**
 * PayPal Service (stub)
 * Proporciona implementaciones mínimas para que el servidor cargue sin errores.
 * Las funciones reales de PayPal se implementarán cuando se requiera el módulo de pagos.
 */

const paypalService = {
  async createOrder(body, context) {
    throw Object.assign(new Error('PayPal no está configurado'), { statusCode: 501, code: 'PAYPAL_NOT_CONFIGURED' });
  },
  async captureOrder(body, context) {
    throw Object.assign(new Error('PayPal no está configurado'), { statusCode: 501, code: 'PAYPAL_NOT_CONFIGURED' });
  },
  async createSubscription(body, context) {
    throw Object.assign(new Error('PayPal no está configurado'), { statusCode: 501, code: 'PAYPAL_NOT_CONFIGURED' });
  },
  async initializePayPal(context) {
    return { configured: false, message: 'PayPal no está configurado' };
  },
  async getPaymentStatus(query, context) {
    throw Object.assign(new Error('PayPal no está configurado'), { statusCode: 501, code: 'PAYPAL_NOT_CONFIGURED' });
  },
  async cancelSubscription(body, context) {
    throw Object.assign(new Error('PayPal no está configurado'), { statusCode: 501, code: 'PAYPAL_NOT_CONFIGURED' });
  },
  async processWebhook(body, context) {
    console.warn('[paypal:webhook] recibido pero PayPal no está configurado');
    return { ok: false, code: 'PAYPAL_NOT_CONFIGURED', message: 'PayPal no está configurado' };
  }
};

module.exports = paypalService;
