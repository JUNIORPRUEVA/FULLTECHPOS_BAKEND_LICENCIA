const express = require('express');
const controller = require('../controllers/storePublicController');

const router = express.Router();

router.get('/store-settings', controller.getPublicSettings);
router.get('/products', controller.listPublishedProducts);
router.get('/products/:slug', controller.getPublishedProductDetail);

module.exports = router;
