const express = require('express');
const controller = require('./backup.controller');

const router = express.Router();

router.post('/push', controller.push);
router.get('/pull', controller.pull);
router.get('/history', controller.history);

module.exports = router;
