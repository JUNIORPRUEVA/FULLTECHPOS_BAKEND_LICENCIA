const express = require('express');
const supportRequestController = require('../controllers/supportRequestController');

const router = express.Router();

// POST /api/support/request
router.post('/request', (req, res, next) => {
  Promise.resolve(supportRequestController.requestSupport(req, res)).catch(next);
});

module.exports = router;
