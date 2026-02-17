const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminSupportMessageConfigController = require('../controllers/adminSupportMessageConfigController');

const router = express.Router();

// GET /api/admin/support-message-config
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminSupportMessageConfigController.getConfig(req, res)).catch(next);
});

// PUT /api/admin/support-message-config
router.put('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminSupportMessageConfigController.updateConfig(req, res)).catch(next);
});

module.exports = router;
