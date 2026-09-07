const commercialModel = require('../models/daleventasCommercialModel');
const daleventasLicenseBridge = require('./daleventasLicenseController');

function technicalPlanValue(profile) {
  const code = String(profile?.plan_code_snapshot || '').trim().toUpperCase();
  if (code === 'PRO') return 'ENTERPRISE';
  if (code === 'BASIC' || code === 'BUSINESS') return 'STANDARD';
  return undefined;
}

function supportedLicensePatch(profile, reason, options = {}) {
  const entitlements = profile?.effective_entitlements || {};
  const body = {};
  const plan = technicalPlanValue(profile);
  if (plan) body.plan = plan;
  if (entitlements.maxUsers != null) body.maxUsers = entitlements.maxUsers;
  if (entitlements.maxProducts != null) body.maxProducts = entitlements.maxProducts;
  if (Object.prototype.hasOwnProperty.call(options, 'expiresAt')) {
    body.expiresAt = options.expiresAt;
  }
  if (reason) body.notes = reason;
  return body;
}

async function propagateSupportedLicensePatch(req, profile, reason, options = {}) {
  const patch = supportedLicensePatch(profile, reason, options);
  const result = await daleventasLicenseBridge.requestDaleVentasJson(
    req,
    'PATCH',
    `/license/admin/${encodeURIComponent(req.params.companyId)}`,
    patch
  );
  if (!result.ok) {
    const error = new Error(
      result.data?.message || 'DaleVentas rechazo la actualizacion de limites.'
    );
    error.status = result.status;
    error.payload = result.data;
    throw error;
  }
  const usage = await daleventasLicenseBridge.requestDaleVentasJson(
    req,
    'GET',
    `/license/admin/${encodeURIComponent(req.params.companyId)}/usage`,
    null
  );
  return {
    propagatedLicense: result.data,
    authoritativeUsage: usage.ok ? usage.data : null
  };
}

function actorFromReq(req) {
  return {
    adminUser: req.adminUser,
    adminUserId: req.adminUserId,
    ip: req.ip,
    headers: req.headers
  };
}

function sendError(res, error) {
  const message = String(error?.message || error || 'Error interno');
  const status = error?.status || (/no encontrado/i.test(message) ? 404 : 400);
  return res.status(status).json({
    ok: false,
    success: false,
    message,
    details: error?.payload
  });
}

async function listPlans(req, res) {
  try {
    const plans = await commercialModel.listPlans(req.query || {});
    return res.json({ ok: true, success: true, plans });
  } catch (error) {
    return sendError(res, error);
  }
}

async function getPlan(req, res) {
  try {
    const plan = await commercialModel.getPlanById(req.params.planId);
    if (!plan) return res.status(404).json({ ok: false, success: false, message: 'Plan no encontrado' });
    return res.json({ ok: true, success: true, plan });
  } catch (error) {
    return sendError(res, error);
  }
}

async function createPlan(req, res) {
  try {
    const plan = await commercialModel.createPlan(req.body || {});
    return res.status(201).json({ ok: true, success: true, plan });
  } catch (error) {
    const status = String(error?.code || '') === '23505' ? 409 : 400;
    return res.status(status).json({ ok: false, success: false, message: String(error.message || error) });
  }
}

async function updatePlan(req, res) {
  try {
    const plan = await commercialModel.updatePlan(req.params.planId, req.body || {});
    if (!plan) return res.status(404).json({ ok: false, success: false, message: 'Plan no encontrado' });
    return res.json({ ok: true, success: true, plan });
  } catch (error) {
    return sendError(res, error);
  }
}

async function listProfiles(req, res) {
  try {
    const data = await commercialModel.listProfiles(req.query || {});
    return res.json({ ok: true, success: true, ...data });
  } catch (error) {
    return sendError(res, error);
  }
}

async function getProfile(req, res) {
  try {
    const profile = await commercialModel.getProfile(req.params.companyId);
    if (!profile) return res.status(404).json({ ok: false, success: false, message: 'Perfil comercial no encontrado' });
    return res.json({ ok: true, success: true, profile });
  } catch (error) {
    return sendError(res, error);
  }
}

async function ensureProfile(req, res) {
  try {
    const profile = await commercialModel.ensureProfileForCompany({
      id: req.params.companyId,
      ...(req.body || {})
    });
    return res.status(201).json({ ok: true, success: true, profile });
  } catch (error) {
    return sendError(res, error);
  }
}

async function updateProfile(req, res) {
  try {
    const profile = await commercialModel.updateProfile(req.params.companyId, req.body || {}, actorFromReq(req));
    if (!profile) return res.status(404).json({ ok: false, success: false, message: 'Perfil comercial no encontrado' });
    return res.json({ ok: true, success: true, profile });
  } catch (error) {
    return sendError(res, error);
  }
}

async function getOverrides(req, res) {
  try {
    const profile = await commercialModel.getProfile(req.params.companyId);
    if (!profile) return res.status(404).json({ ok: false, success: false, message: 'Perfil comercial no encontrado' });
    return res.json({
      ok: true,
      success: true,
      overrides: {
        expirationDate: profile.override_expiration_date,
        extraDays: profile.override_extra_days,
        maxUsers: profile.override_max_users,
        maxProducts: profile.override_max_products,
        maxWarehouses: profile.override_max_warehouses,
        maxDevices: profile.override_max_devices,
        notes: profile.override_notes,
        reason: profile.override_reason,
        updatedAt: profile.override_updated_at,
        updatedBy: profile.override_updated_by
      },
      effectiveEntitlements: profile.effective_entitlements
    });
  } catch (error) {
    return sendError(res, error);
  }
}

async function updateOverrides(req, res) {
  try {
    const profile = await commercialModel.updateOverrides(req.params.companyId, req.body || {}, actorFromReq(req));
    const hasExplicitExpiration =
      Object.prototype.hasOwnProperty.call(req.body || {}, 'expirationDate') ||
      Object.prototype.hasOwnProperty.call(req.body || {}, 'override_expiration_date');
    const propagation = await propagateSupportedLicensePatch(
      req,
      profile,
      req.body?.reason,
      hasExplicitExpiration
        ? { expiresAt: req.body?.expirationDate ?? req.body?.override_expiration_date ?? null }
        : {}
    );
    return res.json({
      ok: true,
      success: true,
      profile,
      effectiveEntitlements: profile.effective_entitlements,
      ...propagation
    });
  } catch (error) {
    return sendError(res, error);
  }
}

async function assignPlan(req, res) {
  try {
    const profile = await commercialModel.assignPlan(req.params.companyId, req.body || {}, actorFromReq(req));
    const propagation = await propagateSupportedLicensePatch(req, profile, req.body?.reason);
    return res.json({
      ok: true,
      success: true,
      profile,
      effectiveEntitlements: profile.effective_entitlements,
      ...propagation
    });
  } catch (error) {
    return sendError(res, error);
  }
}

async function listAudit(req, res) {
  try {
    const auditLogs = await commercialModel.listAudit(req.params.companyId, req.query || {});
    return res.json({ ok: true, success: true, auditLogs });
  } catch (error) {
    return sendError(res, error);
  }
}

async function dashboard(req, res) {
  try {
    const [plans, profiles] = await Promise.all([
      commercialModel.listPlans({ active: true }),
      commercialModel.listProfiles({ limit: 1 })
    ]);
    return res.json({
      ok: true,
      success: true,
      trialDays: 7,
      minimumBillingMonths: 3,
      plans,
      totals: {
        commercialProfiles: profiles.total
      },
      filters: {
        primary: ['TODOS', 'DEMO', 'COMPRARON', 'ACTIVOS', 'POR_VENCER', 'VENCIDOS', 'BLOQUEADOS', 'SEGUIMIENTO'],
        plans: ['BASIC', 'BUSINESS', 'PRO', 'LEGACY', 'CUSTOM'],
        expiration: ['HOY', '7_DIAS', '15_DIAS', '30_DIAS'],
        marketing: ['WEB', 'WHATSAPP', 'FACEBOOK', 'INSTAGRAM', 'REFERIDO', 'DIRECTO', 'OTRO']
      }
    });
  } catch (error) {
    return sendError(res, error);
  }
}

module.exports = {
  listPlans,
  getPlan,
  createPlan,
  updatePlan,
  listProfiles,
  getProfile,
  ensureProfile,
  updateProfile,
  getOverrides,
  updateOverrides,
  assignPlan,
  listAudit,
  dashboard,
  _test: {
    supportedLicensePatch,
    technicalPlanValue
  }
};
