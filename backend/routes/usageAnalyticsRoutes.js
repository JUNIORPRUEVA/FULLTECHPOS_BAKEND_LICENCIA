const express = require('express');
const usageAnalyticsController = require('../controllers/usageAnalyticsController');

const router = express.Router();

router.post('/heartbeat', (req, res, next) => {
  Promise.resolve(usageAnalyticsController.heartbeat(req, res)).catch(next);
});

router.post('/event', (req, res, next) => {
  Promise.resolve(usageAnalyticsController.event(req, res)).catch(next);
});

router.post('/events', (req, res, next) => {
  Promise.resolve(usageAnalyticsController.batch(req, res)).catch(next);
});

router.post('/batch', (req, res, next) => {
  Promise.resolve(usageAnalyticsController.batch(req, res)).catch(next);
});

module.exports = router;
