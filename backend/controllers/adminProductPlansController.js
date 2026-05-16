const productPlansModel = require('../models/productPlansModel');
const auditLogService = require('../services/auditLogService');
const paypalService = require('../services/paypalService');

function asUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

async function listPlans(req, res) {
  try {
    const data = await productPlansModel.list({
      product_id: asUuid(req.query.product_id),
      project_id: asUuid(req.query.project_id),
      is_active: req.query.is_active === undefined ? undefined : String(req.query.is_active) === 'true',
      q: req.query.q ? String(req.query.q) : undefined,
      limit: Math.min(200, Math.max(1, Number(req.query.limit) || 50)),
      offset: Math.max(0, Number(req.query.offset) || 0)
    });
    return res.json({ ok: true, ...data });
  } catch (error) {
    console.error('listPlans error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function getPlan(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });
    const plan = await productPlansModel.getById(id);
    if (!plan) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, plan });
  } catch (error) {
    console.error('getPlan error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function createPlan(req, res) {
  try {
    const plan = await productPlansModel.create(req.body || {});
    await auditLogService.log({
      product_id: plan.product_id,
      project_id: plan.project_id,
      target_type: 'plan',
      target_id: plan.id,
      action: 'plan.create',
      after_data: plan
    }, { req });
    return res.status(201).json({ ok: true, plan });
  } catch (error) {
    const code = String(error?.code || '');
    const message = String(error?.message || 'Error interno');
    return res.status(code === '23505' ? 409 : 400).json({ ok: false, message });
  }
}

async function updatePlan(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });
    const before = await productPlansModel.getById(id);
    if (!before) return res.status(404).json({ ok: false, message: 'No encontrado' });

    const plan = await productPlansModel.update(id, req.body || {});
    await auditLogService.log({
      product_id: plan.product_id,
      project_id: plan.project_id,
      target_type: 'plan',
      target_id: plan.id,
      action: 'plan.update',
      before_data: before,
      after_data: plan
    }, { req });
    return res.json({ ok: true, plan });
  } catch (error) {
    const code = String(error?.code || '');
    const message = String(error?.message || 'Error interno');
    return res.status(code === '23505' ? 409 : 400).json({ ok: false, message });
  }
}

async function setEnabled(req, res, enabled) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });
    const before = await productPlansModel.getById(id);
    if (!before) return res.status(404).json({ ok: false, message: 'No encontrado' });

    const plan = await productPlansModel.setActive(id, enabled);
    await auditLogService.log({
      product_id: plan.product_id,
      project_id: plan.project_id,
      target_type: 'plan',
      target_id: plan.id,
      action: enabled ? 'plan.enable' : 'plan.disable',
      before_data: before,
      after_data: plan
    }, { req });
    return res.json({ ok: true, plan });
  } catch (error) {
    console.error('setEnabled plan error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function enablePlan(req, res) {
  return setEnabled(req, res, true);
}

async function disablePlan(req, res) {
  return setEnabled(req, res, false);
}

async function syncPlanToPayPal(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });
    const plan = await paypalService.syncPlanToPayPal(id, { req });
    return res.json({ ok: true, plan, paypal_plan_id: plan.paypal_plan_id });
  } catch (error) {
    const status = error.statusCode || 400;
    return res.status(status).json({ ok: false, message: String(error?.message || error) });
  }
}

async function syncRecurringPlansToPayPal(req, res) {
  try {
    const result = await paypalService.syncRecurringPlansToPayPal({ req });
    return res.json({ ok: true, ...result });
  } catch (error) {
    const status = error.statusCode || 400;
    return res.status(status).json({ ok: false, message: String(error?.message || error) });
  }
}

module.exports = {
  listPlans,
  getPlan,
  createPlan,
  updatePlan,
  enablePlan,
  disablePlan,
  syncPlanToPayPal,
  syncRecurringPlansToPayPal
};