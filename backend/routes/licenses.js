// Router legacy (compatibilidad). Ya no se monta en server.js.
const express = require('express');
const adminCustomersRoutes = require('./adminCustomersRoutes');
const adminLicensesRoutes = require('./adminLicensesRoutes');
const licensesPublicRoutes = require('./licensesPublicRoutes');

const router = express.Router();
router.use('/admin/customers', adminCustomersRoutes);
router.use('/admin/licenses', adminLicensesRoutes);
router.use('/licenses', licensesPublicRoutes);

module.exports = router;
