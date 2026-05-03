const paymentsModel = require('../models/paymentsModel');
const paymentService = require('../services/paymentService');

function asUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

async function listPayments(req, res) {
  try {
    const data = await paymentsModel.list({
      company_id: asUuid(req.query.company_id),
      subscription_id: asUuid(req.query.subscription_id),
      status: req.query.status ? String(req.query.status).trim().toLowerCase() : undefined,
      product_id: asUuid(req.query.product_id),
      project_id: asUuid(req.query.project_id),
      license_id: asUuid(req.query.license_id),
      limit: Math.min(200, Math.max(1, Number(req.query.limit) || 50)),
      offset: Math.max(0, Number(req.query.offset) || 0)
    });
    return res.json({ ok: true, ...data });
  } catch (error) {
    console.error('listPayments error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function getPayment(req, res) {
  try {
    const id = asUuid(req.params.id);
    if (!id) return res.status(400).json({ ok: false, message: 'id inválido' });
    const payment = await paymentsModel.getById(id);
    if (!payment) return res.status(404).json({ ok: false, message: 'No encontrado' });
    return res.json({ ok: true, payment });
  } catch (error) {
    console.error('getPayment error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function registerManualPayment(req, res) {
  try {
    const result = await paymentService.registerManualPayment(req.body || {}, { req });
    return res.status(result.idempotent ? 200 : 201).json({ ok: true, ...result });
  } catch (error) {
    const message = String(error?.message || error);
    const status = message.includes('no encontrada') || message.includes('no existe') ? 404 : 400;
    return res.status(status).json({ ok: false, message });
  }
}

module.exports = {
  listPayments,
  getPayment,
  registerManualPayment
};