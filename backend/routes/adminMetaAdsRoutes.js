const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminMetaAdsController');

const router = express.Router();

router.use(isAdmin);

// GET /api/admin/meta-ads/config
router.get('/config', controller.getConfig);

// PUT /api/admin/meta-ads/config
router.put('/config', controller.updateConfig);

// POST /api/admin/meta-ads/test-connection
router.post('/test-connection', controller.testConnection);

// POST /api/admin/meta-ads/campaigns
router.post('/campaigns', controller.createCampaign);

module.exports = router;
