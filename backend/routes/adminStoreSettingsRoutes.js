const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminStoreSettingsController');

const router = express.Router();

router.use(isAdmin);

router.get('/store-settings', controller.getSettings);
router.put('/store-settings', controller.updateSettings);

module.exports = router;
