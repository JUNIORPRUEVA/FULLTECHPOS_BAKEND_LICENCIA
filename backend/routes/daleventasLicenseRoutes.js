const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const controller = require('../controllers/daleventasLicenseController');

const router = express.Router();

router.get('/companies', isAdmin, (req, res, next) => {
  Promise.resolve(controller.listCompanies(req, res)).catch(next);
});

router.get('/companies/:companyId', isAdmin, (req, res, next) => {
  Promise.resolve(controller.getCompany(req, res)).catch(next);
});

router.patch('/companies/:companyId', isAdmin, (req, res, next) => {
  Promise.resolve(controller.updateCompany(req, res)).catch(next);
});

router.post('/companies/:companyId/activate', isAdmin, (req, res, next) => {
  Promise.resolve(controller.activateCompany(req, res)).catch(next);
});

router.post('/companies/:companyId/block', isAdmin, (req, res, next) => {
  Promise.resolve(controller.blockCompany(req, res)).catch(next);
});

router.delete('/companies/:companyId', isAdmin, (req, res, next) => {
  Promise.resolve(controller.deleteCompanyLicense(req, res)).catch(next);
});

router.delete('/companies/:companyId/permanent', isAdmin, (req, res, next) => {
  Promise.resolve(controller.permanentlyDeleteCompanyLicense(req, res)).catch(next);
});

module.exports = router;
