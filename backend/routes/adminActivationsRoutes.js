const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminActivationsController = require('../controllers/adminActivationsController');

const router = express.Router();

// GET /api/admin/activations
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminActivationsController.listActivations(req, res)).catch(next);
});

// PATCH /api/admin/activations/:id/revocar
router.patch('/:id/revocar', isAdmin, (req, res, next) => {
  Promise.resolve(adminActivationsController.revokeActivation(req, res)).catch(next);
});

module.exports = router;
