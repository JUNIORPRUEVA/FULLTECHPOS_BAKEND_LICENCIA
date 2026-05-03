const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminMaintenanceController');

const router = express.Router();

router.use(isAdmin);

// POST /api/admin/subscriptions/run-maintenance
router.post('/run-maintenance', controller.runMaintenance);

module.exports = router;
