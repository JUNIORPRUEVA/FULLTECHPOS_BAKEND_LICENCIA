const subscriptionsModel = require('../models/subscriptionsModel');
const subscriptionService = require('../services/subscriptionService');

function asUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

async function listSubscriptions(req, res) {
  try {
    const data = await subscriptionsModel.list({
      company_id: asUuid(req.query.company_id),
      status: req.query.status ? String(req.query.status).trim().toLowerCase() : undefined,
      product_id: asUuid(req.query.product_id),
      project_id: asUuid(req.query.project_id),
      plan_id: asUuid(req.query.plan_id),
      limit: Math.min(200, Math.max(1, Number(req.query.limit) || 50)),
      offset: Math.max(0, Number(req.query.offset) || 0)
    });
    return res.json({ ok: true, ...data });
  } catch (error) {
    console.error('listSubscriptions error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function getSubscription(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });
    const subscription = await subscriptionsModel.getById(id);
    if (!subscription) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, subscription });
  } catch (error) {
    console.error('getSubscription error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function createSubscription(req, res) {
  try {
    const subscription = await subscriptionService.createSubscription(req.body || {}, { req });
    return res.status(201).json({ ok: true, subscription });
  } catch (error) {
    return res.status(400).json({ ok: false, message: String(error?.message || error) });
  }
}

async function updateSubscriptionStatus(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });
    const status = String(req.body?.status || '').trim().toLowerCase();
    const subscription = await subscriptionService.updateStatus(id, status, req.body || {}, { req });
    return res.json({ ok: true, subscription });
  } catch (error) {
    const message = String(error?.message || error);
    return res.status(message.includes('no encontrada') ? 404 : 400).json({ ok: false, message });
  }
}

async function extendSubscription(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });
    const subscription = await subscriptionService.extendDates(id, req.body || {}, { req });
    return res.json({ ok: true, subscription });
  } catch (error) {
    const message = String(error?.message || error);
    return res.status(message.includes('no encontrada') ? 404 : 400).json({ ok: false, message });
  }
}

async function cancelSubscription(req, res) {
  req.body = { ...(req.body || {}), status: 'cancelled' };
  return updateSubscriptionStatus(req, res);
}

async function suspendSubscription(req, res) {
  req.body = { ...(req.body || {}), status: 'suspended' };
  return updateSubscriptionStatus(req, res);
}

module.exports = {
  listSubscriptions,
  getSubscription,
  createSubscription,
  updateSubscriptionStatus,
  extendSubscription,
  cancelSubscription,
  suspendSubscription
};