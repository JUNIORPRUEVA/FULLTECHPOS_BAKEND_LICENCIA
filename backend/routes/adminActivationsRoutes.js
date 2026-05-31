const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminActivationsController = require('../controllers/adminActivationsController');

const router = express.Router();

// GET /api/admin/activations
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminActivationsController.listActivations(req, res)).catch(next);
});

// GET /api/admin/activations/:id
router.get('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminActivationsController.getActivation(req, res)).catch(next);
});

// POST /api/admin/activations/:id/block
router.post('/:id/block', isAdmin, (req, res, next) => {
  Promise.resolve(adminActivationsController.blockActivation(req, res)).catch(next);
});

// POST /api/admin/activations/:id/revoke
router.post('/:id/revoke', isAdmin, (req, res, next) => {
  Promise.resolve(adminActivationsController.revokeActivation(req, res)).catch(next);
});

// PATCH /api/admin/activations/:id/revocar
router.patch('/:id/revocar', isAdmin, (req, res, next) => {
  Promise.resolve(adminActivationsController.revokeActivation(req, res)).catch(next);
});

// POST /api/admin/activations/:id/activate
router.post('/:id/activate', isAdmin, (req, res, next) => {
  Promise.resolve(adminActivationsController.activateActivation(req, res)).catch(next);
});

module.exports = router;
