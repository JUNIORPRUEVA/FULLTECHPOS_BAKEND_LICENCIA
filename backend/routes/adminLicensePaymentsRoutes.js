const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminLicensePaymentsController = require('../controllers/adminLicensePaymentsController');

const router = express.Router();

// POST /api/admin/license-payments/create-paypal-order
router.post('/create-paypal-order', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensePaymentsController.createPayPalOrder(req, res)).catch(next);
});

// POST /api/admin/license-payments/capture-paypal-order
router.post('/capture-paypal-order', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensePaymentsController.capturePayPalOrder(req, res)).catch(next);
});

// GET /api/admin/license-payments
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensePaymentsController.listPaymentOrders(req, res)).catch(next);
});

// GET /api/admin/license-payments/:id
router.get('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensePaymentsController.getPaymentOrderDetail(req, res)).catch(next);
});

// POST /api/admin/licenses/demo
router.post('/demo', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensePaymentsController.createDemoLicense(req, res)).catch(next);
});

// GET /api/admin/license-payments/paypal/health
router.get('/paypal/health', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensePaymentsController.paypalHealth(req, res)).catch(next);
});

module.exports = router;
