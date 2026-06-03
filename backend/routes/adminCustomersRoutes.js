const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminCustomersController = require('../controllers/adminCustomersController');

const router = express.Router();

// POST /api/admin/customers
router.post('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.createCustomer(req, res)).catch(next);
});

// GET /api/admin/customers
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.listCustomers(req, res)).catch(next);
});

// GET /api/admin/customers/by-business/:businessId
router.get('/by-business/:businessId', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.getCustomerByBusinessId(req, res)).catch(next);
});

// GET /api/admin/customers/:id
router.get('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.getCustomerById(req, res)).catch(next);
});

// GET /api/admin/customers/:id/licenses
router.get('/:id/licenses', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.getCustomerLicenses(req, res)).catch(next);
});

// GET /api/admin/customers/:id/payments
router.get('/:id/payments', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.getCustomerPayments(req, res)).catch(next);
});

// POST /api/admin/customers/:id/assign-business-id
router.post('/:id/assign-business-id', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.assignBusinessId(req, res)).catch(next);
});

// POST /api/admin/customers/:id/business_id/repair
router.post('/:id/business_id/repair', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.repairBusinessId(req, res)).catch(next);
});

// POST /api/admin/customers/:id/reset-token
router.post('/:id/reset-token', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.resetToken(req, res)).catch(next);
});

// DELETE /api/admin/customers/:id
router.delete('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.deleteCustomer(req, res)).catch(next);
});

// PUT /api/admin/customers/:id/business_id
router.put('/:id/business_id', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.setBusinessId(req, res)).catch(next);
});

// PUT /api/admin/customers/:id
router.put('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.updateCustomer(req, res)).catch(next);
});

// PATCH /api/admin/customers/:id
router.patch('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.updateCustomer(req, res)).catch(next);
});

module.exports = router;
