const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminProductPlansController');

const router = express.Router();

router.use(isAdmin);

router.get('/', controller.listPlans);
router.get('/:id', controller.getPlan);
router.post('/', controller.createPlan);
router.patch('/:id', controller.updatePlan);
router.patch('/:id/enable', controller.enablePlan);
router.patch('/:id/disable', controller.disablePlan);

module.exports = router;