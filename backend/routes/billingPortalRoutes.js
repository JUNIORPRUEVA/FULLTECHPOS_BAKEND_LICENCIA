const express = require('express');
const sessions = require('../auth/sessions');
const controller = require('../controllers/billingPortalController');

const router = express.Router();

router.get('/plans', (req, res, next) => {
  Promise.resolve(controller.listPlans(req, res, next)).catch(next);
});

router.get('/subscriptions', sessions.verifySessionMiddleware, (req, res, next) => {
  Promise.resolve(controller.listSubscriptions(req, res, next)).catch(next);
});

router.get('/license', sessions.verifySessionMiddleware, (req, res, next) => {
  Promise.resolve(controller.getLicense(req, res, next)).catch(next);
});

module.exports = router;
