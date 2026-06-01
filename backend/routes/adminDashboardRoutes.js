const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminDashboardController = require('../controllers/adminDashboardController');

const router = express.Router();

// GET /api/admin/dashboard-stats
router.get('/dashboard-stats', isAdmin, (req, res, next) => {
  Promise.resolve(adminDashboardController.getDashboardStats(req, res)).catch(next);
});

module.exports = router;
