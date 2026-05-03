const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminSaasDashboardController');

const router = express.Router();

router.use(isAdmin);

// GET /api/admin/saas-dashboard
router.get('/', controller.getDashboard);

module.exports = router;
