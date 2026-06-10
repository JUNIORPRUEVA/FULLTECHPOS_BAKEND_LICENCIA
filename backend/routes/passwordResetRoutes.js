const express = require('express');
const passwordResetController = require('../controllers/passwordResetController');

const router = express.Router();

// POST /api/password-reset/support-token/confirm
router.post('/support-token/confirm', (req, res, next) => {
  Promise.resolve(passwordResetController.confirmSupportToken(req, res)).catch(next);
});

// POST /api/password-reset/admin-token/validate
// Valida y consume un token de reset generado por el admin para un cliente
router.post('/admin-token/validate', (req, res, next) => {
  Promise.resolve(passwordResetController.validateAdminToken(req, res)).catch(next);
});

module.exports = router;
