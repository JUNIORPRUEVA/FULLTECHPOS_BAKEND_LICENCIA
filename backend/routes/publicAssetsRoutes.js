const express = require('express');
const controller = require('../controllers/publicAssetsController');

const router = express.Router();

// Public media/downloads are controlled (published + active only).
router.get('/media/:filename', controller.serveMedia);
router.get('/download/:filename', controller.serveDownload);

module.exports = router;
