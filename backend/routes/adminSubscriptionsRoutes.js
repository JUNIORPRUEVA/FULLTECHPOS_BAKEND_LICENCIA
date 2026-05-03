const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminSubscriptionsController');

const router = express.Router();

router.use(isAdmin);

router.get('/', controller.listSubscriptions);
router.get('/:id', controller.getSubscription);
router.post('/', controller.createSubscription);
router.patch('/:id/status', controller.updateSubscriptionStatus);
router.patch('/:id/extend', controller.extendSubscription);
router.patch('/:id/cancel', controller.cancelSubscription);
router.patch('/:id/suspend', controller.suspendSubscription);

module.exports = router;