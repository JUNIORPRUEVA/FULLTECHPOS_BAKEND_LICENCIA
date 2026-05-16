const express = require('express');
const paypalController = require('../controllers/paypalController');
const isAdmin = require('../middleware/isAdmin');

const router = express.Router();

router.post('/create-order', (req, res, next) => {
  Promise.resolve(paypalController.createOrder(req, res)).catch(next);
});

router.post('/capture-order', (req, res, next) => {
  Promise.resolve(paypalController.captureOrder(req, res)).catch(next);
});

router.post('/init', isAdmin, (req, res, next) => {
  Promise.resolve(paypalController.initialize(req, res)).catch(next);
});

router.post('/create-subscription', (req, res, next) => {
  Promise.resolve(paypalController.createSubscription(req, res)).catch(next);
});

router.get('/status', (req, res, next) => {
  Promise.resolve(paypalController.status(req, res)).catch(next);
});

router.post('/cancel-subscription', (req, res, next) => {
  Promise.resolve(paypalController.cancelSubscription(req, res)).catch(next);
});

// PayPal Webhooks
// Desarrollo local con ngrok:
//   1) Ejecutar backend en el puerto configurado, normalmente 3000.
//   2) Ejecutar: ngrok http 3000
//   3) Registrar en PayPal la URL publica:
//      https://TU-SUBDOMINIO.ngrok-free.app/api/paypal/webhook
// Produccion:
//   Registrar https://TU-DOMINIO/api/paypal/webhook en PayPal y configurar
//   PAYPAL_WEBHOOK_ID para validar la firma del evento.
router.post('/webhook', (req, res, next) => {
  Promise.resolve(paypalController.webhook(req, res)).catch(next);
});

module.exports = router;
