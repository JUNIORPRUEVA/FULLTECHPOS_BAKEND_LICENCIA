const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminProjectsController = require('../controllers/adminProjectsController');

const router = express.Router();

// GET /api/admin/projects
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminProjectsController.listProjects(req, res)).catch(next);
});

// POST /api/admin/projects
router.post('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminProjectsController.createProject(req, res)).catch(next);
});

module.exports = router;
