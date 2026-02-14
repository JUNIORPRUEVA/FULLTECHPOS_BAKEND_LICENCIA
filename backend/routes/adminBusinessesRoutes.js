const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminBusinessesController = require('../controllers/adminBusinessesController');

const router = express.Router();

// POST /api/admin/businesses/:business_id/activate
router.post('/:business_id/activate', isAdmin, (req, res, next) => {
  Promise.resolve(adminBusinessesController.activateLicenseForBusiness(req, res)).catch(next);
});

module.exports = router;
