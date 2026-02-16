const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminEvolutionConfigController = require('../controllers/adminEvolutionConfigController');

const router = express.Router();

// GET /api/admin/evolution-config
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminEvolutionConfigController.getConfig(req, res)).catch(next);
});

// PUT /api/admin/evolution-config
router.put('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminEvolutionConfigController.updateConfig(req, res)).catch(next);
});

module.exports = router;
