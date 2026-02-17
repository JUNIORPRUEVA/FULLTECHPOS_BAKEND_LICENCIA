const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminSupportResetController = require('../controllers/adminSupportResetController');

const router = express.Router();

// POST /api/admin/support-reset/token
router.post('/token', isAdmin, (req, res, next) => {
  Promise.resolve(adminSupportResetController.createToken(req, res)).catch(next);
});

module.exports = router;
