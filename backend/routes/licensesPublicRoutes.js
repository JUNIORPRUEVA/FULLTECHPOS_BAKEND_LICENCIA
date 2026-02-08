const express = require('express');
const licensesController = require('../controllers/licensesController');
const licensesDemoController = require('../controllers/licensesDemoController');

const router = express.Router();

// POST /api/licenses/activate
router.post('/activate', (req, res, next) => {
  Promise.resolve(licensesController.activate(req, res)).catch(next);
});

// POST /api/licenses/check
router.post('/check', (req, res, next) => {
  Promise.resolve(licensesController.check(req, res)).catch(next);
});

// POST /api/licenses/auto-activate
router.post('/auto-activate', (req, res, next) => {
  Promise.resolve(licensesController.autoActivateByDevice(req, res)).catch(next);
});

// POST /api/licenses/start-demo
router.post('/start-demo', (req, res, next) => {
  Promise.resolve(licensesDemoController.startDemo(req, res)).catch(next);
});

// POST /api/licenses/verify-offline-file
router.post('/verify-offline-file', (req, res, next) => {
  Promise.resolve(licensesController.verifyOfflineFile(req, res)).catch(next);
});

// GET /api/licenses/public-signing-key
router.get('/public-signing-key', (req, res, next) => {
  Promise.resolve(licensesController.getPublicSigningKey(req, res)).catch(next);
});

module.exports = router;
