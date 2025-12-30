const express = require('express');
const licensesController = require('../controllers/licensesController');

const router = express.Router();

// POST /api/licenses/activate
router.post('/activate', (req, res, next) => {
  Promise.resolve(licensesController.activate(req, res)).catch(next);
});

// POST /api/licenses/check
router.post('/check', (req, res, next) => {
  Promise.resolve(licensesController.check(req, res)).catch(next);
});

module.exports = router;
