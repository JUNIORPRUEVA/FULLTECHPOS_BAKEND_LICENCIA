const express = require('express');
const isAdmin = require('../middleware/isAdmin');
const adminLicensesController = require('../controllers/adminLicensesController');

const router = express.Router();

// POST /api/admin/licenses
router.post('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.createLicense(req, res)).catch(next);
});

// GET /api/admin/licenses
router.get('/', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.listLicenses(req, res)).catch(next);
});

// GET /api/admin/licenses/:id
router.get('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.getLicenseDetail(req, res)).catch(next);
});

// PATCH /api/admin/licenses/:id
router.patch('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.updateLicense(req, res)).catch(next);
});

// DELETE /api/admin/licenses/:id
router.delete('/:id', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.deleteLicense(req, res)).catch(next);
});

// PATCH /api/admin/licenses/:id/bloquear
router.patch('/:id/bloquear', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.bloquearLicense(req, res)).catch(next);
});

// PATCH /api/admin/licenses/:id/activar-manual
router.patch('/:id/activar-manual', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.activarManual(req, res)).catch(next);
});

// PATCH /api/admin/licenses/:id/desbloquear
router.patch('/:id/desbloquear', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.desbloquearLicense(req, res)).catch(next);
});

// PATCH /api/admin/licenses/:id/extender-dias
router.patch('/:id/extender-dias', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.extenderDias(req, res)).catch(next);
});

// GET /api/admin/licenses/:id/license-file?device_id=...&download=1
router.get('/:id/license-file', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.exportLicenseFile(req, res)).catch(next);
});

// POST /api/admin/licenses/:id/license-file  { device_id?, ensure_active? }
router.post('/:id/license-file', isAdmin, (req, res, next) => {
  Promise.resolve(adminLicensesController.exportLicenseFile(req, res)).catch(next);
});

module.exports = router;
