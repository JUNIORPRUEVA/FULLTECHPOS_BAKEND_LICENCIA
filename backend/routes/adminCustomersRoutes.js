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

// DELETE /api/admin/customers/:id
router.delete('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.deleteCustomer(req, res)).catch(next);
});

// PUT /api/admin/customers/:id/business_id
router.put('/:id/business_id', isAdmin, (req, res, next) => {
  Promise.resolve(adminCustomersController.setBusinessId(req, res)).catch(next);
});

module.exports = router;
