const express = require('express');
const activationsController = require('../controllers/activationsController');

const router = express.Router();

router.post('/activate', (req, res, next) => {
  Promise.resolve(activationsController.activate(req, res)).catch(next);
});

router.post('/heartbeat', (req, res, next) => {
  Promise.resolve(activationsController.heartbeat(req, res)).catch(next);
});

router.post('/revoke', (req, res, next) => {
  Promise.resolve(activationsController.revoke(req, res)).catch(next);
});

module.exports = router;
