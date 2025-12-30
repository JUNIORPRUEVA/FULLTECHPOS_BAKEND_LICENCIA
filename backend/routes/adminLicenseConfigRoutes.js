const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminLicenseConfigController = require('../controllers/adminLicenseConfigController');

const router = express.Router();

// GET /api/admin/license-config
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicenseConfigController.getConfig(req, res)).catch(next);
});

// PUT /api/admin/license-config
router.put('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicenseConfigController.updateConfig(req, res)).catch(next);
});

module.exports = router;
