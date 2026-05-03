const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/adminPlatformUsersController');

const router = express.Router();

router.use(isAdmin);

router.get('/', controller.listPlatformUsers);
router.post('/', controller.createPlatformUser);
router.post('/:id/roles', controller.assignRole);

module.exports = router;