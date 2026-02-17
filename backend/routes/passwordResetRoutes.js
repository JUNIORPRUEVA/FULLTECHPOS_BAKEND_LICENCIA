const express = require('express');
const passwordResetController = require('../controllers/passwordResetController');

const router = express.Router();

// POST /api/password-reset/request
router.post('/request', (req, res, next) => {
  Promise.resolve(passwordResetController.requestCode(req, res)).catch(next);
});

// POST /api/password-reset/confirm
router.post('/confirm', (req, res, next) => {
  Promise.resolve(passwordResetController.confirmCode(req, res)).catch(next);
});

// POST /api/password-reset/support-token/confirm
router.post('/support-token/confirm', (req, res, next) => {
  Promise.resolve(passwordResetController.confirmSupportToken(req, res)).catch(next);
});

module.exports = router;
