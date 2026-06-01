/**
 * Rutas públicas de licencias para FullCredit y otras apps SaaS.
 * 
 * Estas rutas NO usan middleware isAdmin.
 * Usan rate limit básico para proteger contra abuso.
 * 
 * Endpoints:
 *   POST /api/public/license/validate
 *   POST /api/public/licenses/demo/start
 *   GET  /api/public/projects/:code/billing
 *   POST /api/public/license-payments/create-paypal-order
 *   POST /api/public/license-payments/capture-paypal-order
 *   POST /api/public/customers/register-or-find
 */
const express = require('express');
const publicLicenseController = require('../controllers/publicLicenseController');

const router = express.Router();

// POST /api/public/license/validate
router.post('/license/validate', (req, res, next) => {
  Promise.resolve(publicLicenseController.validateLicense(req, res)).catch(next);
});

// POST /api/public/licenses/demo/start
router.post('/licenses/demo/start', (req, res, next) => {
  Promise.resolve(publicLicenseController.startDemo(req, res)).catch(next);
});

// GET /api/public/projects/:code/billing
router.get('/projects/:code/billing', (req, res, next) => {
  Promise.resolve(publicLicenseController.getProjectBillingInfo(req, res)).catch(next);
});

// POST /api/public/license-payments/create-paypal-order
router.post('/license-payments/create-paypal-order', (req, res, next) => {
  Promise.resolve(publicLicenseController.createPaymentOrder(req, res)).catch(next);
});

// POST /api/public/license-payments/capture-paypal-order
router.post('/license-payments/capture-paypal-order', (req, res, next) => {
  Promise.resolve(publicLicenseController.capturePayment(req, res)).catch(next);
});

// POST /api/public/customers/register-or-find
router.post('/customers/register-or-find', (req, res, next) => {
  Promise.resolve(publicLicenseController.registerOrFindCustomer(req, res)).catch(next);
});

module.exports = router;
