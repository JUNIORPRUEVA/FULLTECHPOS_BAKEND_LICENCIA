const express = require('express');
const adminPaymentsController = require('../controllers/adminPaymentsController');
const isAdmin = require('../middleware/isAdmin');

const router = express.Router();

router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminPaymentsController.listPayments(req, res)).catch(next);
});

module.exports = router;
