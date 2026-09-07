const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminUsageAnalyticsController = require('../controllers/adminUsageAnalyticsController');

const router = express.Router();

router.use(isAdmin);

router.get('/overview', (req, res, next) => {
  Promise.resolve(adminUsageAnalyticsController.overview(req, res)).catch(next);
});

router.get('/accounts', (req, res, next) => {
  Promise.resolve(adminUsageAnalyticsController.accounts(req, res)).catch(next);
});

router.get('/events', (req, res, next) => {
  Promise.resolve(adminUsageAnalyticsController.events(req, res)).catch(next);
});

router.get('/activity/:businessId', (req, res, next) => {
  Promise.resolve(adminUsageAnalyticsController.activity(req, res)).catch(next);
});

module.exports = router;
