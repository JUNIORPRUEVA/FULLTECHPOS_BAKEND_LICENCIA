const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminDaleventasCommercialController');

const router = express.Router();

router.use(isAdmin);

router.get('/dashboard', controller.dashboard);

router.get('/plans', controller.listPlans);
router.post('/plans', controller.createPlan);
router.get('/plans/:planId', controller.getPlan);
router.patch('/plans/:planId', controller.updatePlan);

router.get('/profiles', controller.listProfiles);
router.get('/profiles/:companyId', controller.getProfile);
router.post('/profiles/:companyId', controller.ensureProfile);
router.patch('/profiles/:companyId', controller.updateProfile);
router.post('/profiles/:companyId/assign-plan', controller.assignPlan);
router.get('/profiles/:companyId/overrides', controller.getOverrides);
router.patch('/profiles/:companyId/overrides', controller.updateOverrides);
router.get('/profiles/:companyId/audit', controller.listAudit);

module.exports = router;
