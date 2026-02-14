const { pool } = require('../db/pool');
const customersModel = require('../models/customersModel');
const licensesModel = require('../models/licensesModel');
const projectsModel = require('../models/projectsModel');

function asTrimmed(value) {
  const v = String(value || '').trim();
  return v ? v : '';
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || '').trim());
}

async function resolveProject({ project_id, project_code } = {}) {
  if (project_id) {
    if (!isUuid(project_id)) return null;
    return projectsModel.getProjectById(String(project_id).trim());
  }

  const code = asTrimmed(project_code) || 'FULLPOS';
  let project = await projectsModel.getProjectByCode(code);
  if (!project && code !== 'DEFAULT') project = await projectsModel.getDefaultProject();
  return project;
}

async function getNewestLicenseRow({ customerId, projectId }) {
  const res = await pool.query(
    `SELECT *
     FROM licenses
     WHERE customer_id = $1 AND project_id = $2
     ORDER BY created_at DESC
     LIMIT 1`,
    [customerId, projectId]
  );
  return res.rows[0] || null;
}

async function activateLicenseForBusiness(req, res) {
  try {
    const businessId = asTrimmed(req.params?.business_id);
    if (!businessId) {
      return res.status(400).json({ ok: false, message: 'business_id es requerido' });
    }

    const project = await resolveProject({
      project_id: req.body?.project_id,
      project_code: req.body?.project_code
    });
    if (!project) {
      return res.status(404).json({ ok: false, message: 'Proyecto no encontrado' });
    }

    let customer;
    try {
      customer = await customersModel.getCustomerByBusinessId(businessId);
    } catch (e) {
      if (e && e.code === 'MIGRATION_PENDING') {
        return res.status(501).json({ ok: false, message: 'Migración pendiente: customers.business_id no existe en la BD' });
      }
      throw e;
    }

    if (!customer) {
      return res.status(404).json({ ok: false, code: 'BUSINESS_NOT_FOUND', message: 'Negocio no encontrado' });
    }

    const newest = await getNewestLicenseRow({ customerId: customer.id, projectId: project.id });
    if (!newest) {
      return res.status(404).json({
        ok: false,
        code: 'NO_LICENSE_FOR_BUSINESS',
        message: 'Este negocio no tiene licencias creadas para este proyecto'
      });
    }

    const licenseId = asTrimmed(req.body?.license_id);
    const licenseKey = asTrimmed(req.body?.license_key);

    let chosen = null;

    if (licenseId) {
      if (!isUuid(licenseId)) {
        return res.status(400).json({ ok: false, message: 'license_id inválido' });
      }
      const lic = await licensesModel.getLicenseById(licenseId);
      if (!lic) {
        return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
      }
      if (String(lic.customer_id || '') !== String(customer.id)) {
        return res.status(409).json({ ok: false, code: 'LICENSE_CUSTOMER_MISMATCH', message: 'La licencia no pertenece a este negocio' });
      }
      if (String(lic.project_id || '') !== String(project.id)) {
        return res.status(409).json({ ok: false, code: 'LICENSE_PROJECT_MISMATCH', message: 'La licencia no corresponde a este proyecto' });
      }
      chosen = lic;
    } else if (licenseKey) {
      const lic = await licensesModel.findLicenseByKey(licenseKey);
      if (!lic) {
        return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
      }
      if (String(lic.customer_id || '') !== String(customer.id)) {
        return res.status(409).json({ ok: false, code: 'LICENSE_CUSTOMER_MISMATCH', message: 'La licencia no pertenece a este negocio' });
      }
      if (String(lic.project_id || '') !== String(project.id)) {
        return res.status(409).json({ ok: false, code: 'LICENSE_PROJECT_MISMATCH', message: 'La licencia no corresponde a este proyecto' });
      }
      chosen = lic;
    } else {
      chosen = newest;
    }

    // IMPORTANT: the public /businesses/:business_id/license endpoint stops if the newest license is BLOQUEADA.
    // If admin tries to activate an older license while there is a newer blocked one, cloud will still return 204.
    const newestEstado = String(newest.estado || '').toUpperCase();
    if (newestEstado === 'BLOQUEADA' && String(newest.id) !== String(chosen.id)) {
      return res.status(409).json({
        ok: false,
        code: 'NEWER_BLOCKED_LICENSE',
        message: 'Existe una licencia más reciente BLOQUEADA. Debes desbloquear/activar esa licencia o crear una nueva.'
      });
    }

    const updated = await licensesModel.activateLicenseManually(String(chosen.id));
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Licencia no encontrada' });
    }

    return res.json({
      ok: true,
      business_id: businessId,
      customer_id: customer.id,
      project_code: project.code,
      license: updated
    });
  } catch (error) {
    console.error('adminBusinesses.activateLicenseForBusiness error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  activateLicenseForBusiness
};
