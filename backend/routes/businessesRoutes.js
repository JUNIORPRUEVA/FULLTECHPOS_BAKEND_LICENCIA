const express = require('express');
const businessesController = require('../controllers/businessesController');

const router = express.Router();

// POST /businesses/register
router.post('/register', (req, res, next) => {
  Promise.resolve(businessesController.register(req, res)).catch(next);
});

// GET /businesses/:business_id/license
router.get('/:business_id/license', (req, res, next) => {
  Promise.resolve(businessesController.getLicense(req, res)).catch(next);
});

module.exports = router;
