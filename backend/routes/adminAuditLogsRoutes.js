const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminAuditLogsController');

const router = express.Router();

router.use(isAdmin);

router.get('/', controller.listAuditLogs);

module.exports = router;