const express = require('express');
const controller = require('./sync.controller');

const router = express.Router();

router.post('/push', controller.push);
router.get('/pull', controller.pull);

module.exports = router;
