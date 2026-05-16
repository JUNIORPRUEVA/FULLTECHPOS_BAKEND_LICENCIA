const paypalService = require('../services/paypalService');

function sendError(res, error) {
  const status = error.statusCode || 500;
  if (status >= 500) console.error('paypalController error:', error);
  return res.status(status).json({
    ok: false,
    code: error.code || 'PAYPAL_ERROR',
    message: error.message || 'Error procesando PayPal'
  });
}

async function createOrder(req, res) {
  try {
    const result = await paypalService.createOrder(req.body || {}, { req });
    return res.status(201).json({ ok: true, ...result });
  } catch (error) {
    return sendError(res, error);
  }
}

async function captureOrder(req, res) {
  try {
    const result = await paypalService.captureOrder(req.body || {}, { req });
    return res.json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

async function createSubscription(req, res) {
  try {
    const result = await paypalService.createSubscription(req.body || {}, { req });
    return res.status(201).json({ ok: true, ...result });
  } catch (error) {
    return sendError(res, error);
  }
}

async function status(req, res) {
  try {
    const result = await paypalService.getPaymentStatus(req.query || {}, { req });
    return res.json({ ok: true, ...result });
  } catch (error) {
    return sendError(res, error);
  }
}

async function cancelSubscription(req, res) {
  try {
    const result = await paypalService.cancelSubscription(req.body || {}, { req });
    return res.json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

async function webhook(req, res) {
  try {
    const result = await paypalService.processWebhook(req.body || {}, { req });
    return res.json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

module.exports = {
  createOrder,
  captureOrder,
  createSubscription,
  status,
  cancelSubscription,
  webhook
};
