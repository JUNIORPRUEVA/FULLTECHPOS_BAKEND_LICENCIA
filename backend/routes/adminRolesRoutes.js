const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminRolesController');

const router = express.Router();

router.use(isAdmin);

router.get('/', controller.listRoles);
router.get('/permissions', controller.listPermissions);

module.exports = router;