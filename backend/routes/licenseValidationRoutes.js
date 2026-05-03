const express = require('express');
const controller = require('../controllers/licenseValidationController');

const router = express.Router();

router.post('/validate', controller.validate);

module.exports = router;