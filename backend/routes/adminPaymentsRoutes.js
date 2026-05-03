const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminPaymentsController');

const router = express.Router();

router.use(isAdmin);

router.get('/', controller.listPayments);
router.get('/:id', controller.getPayment);
router.post('/', controller.registerManualPayment);

module.exports = router;