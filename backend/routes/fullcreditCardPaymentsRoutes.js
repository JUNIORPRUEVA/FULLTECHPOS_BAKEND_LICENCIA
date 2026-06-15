const express = require('express');
const controller = require('../controllers/fullcreditCardPaymentsController');

const router = express.Router();

router.post('/fullcredit/card-payments/orders', (req, res, next) => {
  Promise.resolve(controller.createOrder(req, res)).catch(next);
});

router.post('/fullcredit/card-payments/orders/capture', (req, res, next) => {
  Promise.resolve(controller.captureOrder(req, res)).catch(next);
});

router.get('/fullcredit/card-payments/orders/:id/status', (req, res, next) => {
  Promise.resolve(controller.status(req, res)).catch(next);
});

router.post('/fullcredit/card-payments/orders/cancel', (req, res, next) => {
  Promise.resolve(controller.cancelOrder(req, res)).catch(next);
});

module.exports = router;
