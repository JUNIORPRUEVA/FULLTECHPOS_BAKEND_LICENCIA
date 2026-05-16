const express = require('express');
const paypalController = require('../controllers/paypalController');

const router = express.Router();

router.post('/create-order', (req, res, next) => {
  Promise.resolve(paypalController.createOrder(req, res)).catch(next);
});

router.post('/capture-order', (req, res, next) => {
  Promise.resolve(paypalController.captureOrder(req, res)).catch(next);
});

router.post('/create-subscription', (req, res, next) => {
  Promise.resolve(paypalController.createSubscription(req, res)).catch(next);
});

router.post('/webhook', (req, res, next) => {
  Promise.resolve(paypalController.webhook(req, res)).catch(next);
});

module.exports = router;
