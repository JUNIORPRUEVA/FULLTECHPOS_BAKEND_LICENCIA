const crypto = require('crypto');
const paypalService = require('../services/paypalService');
const model = require('../models/fullcreditCardPaymentsModel');

const PROJECT_CODE = 'FULLCREDIT';
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function text(value, max = 255) {
  return String(value || '').trim().slice(0, max);
}

function publicBaseUrl(req) {
  const proto =
    text(req.headers['x-forwarded-proto']) || text(req.protocol) || 'https';
  const host = text(req.headers['x-forwarded-host']) || text(req.get('host'));
  return `${proto}://${host}`.replace(/\/+$/, '');
}

function tokenHash(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

function tokenMatches(order, token) {
  const provided = Buffer.from(tokenHash(token), 'hex');
  const expected = Buffer.from(String(order.public_token_hash || ''), 'hex');
  return (
    provided.length === expected.length &&
    provided.length > 0 &&
    crypto.timingSafeEqual(provided, expected)
  );
}

function publicOrder(order) {
  return {
    payment_order_id: order.id,
    project_code: order.project_code,
    payment_reference: order.payment_reference,
    amount: Number(order.amount),
    currency: order.currency,
    status: order.status,
    provider_order_id: order.provider_order_id || null,
    provider_capture_id: order.provider_capture_id || null,
    checkout_url: order.checkout_url || null,
    paid_at: order.paid_at || null,
  };
}

async function createOrder(req, res) {
  const projectCode = text(req.body?.project_code, 50).toUpperCase();
  const businessId = text(req.body?.business_id);
  const deviceId = text(req.body?.device_id);
  const paymentReference = text(req.body?.payment_reference, 36);
  const publicToken = text(req.body?.payment_token, 200);
  const amount = Number(req.body?.amount);
  const requestedCurrency = text(req.body?.currency, 10).toUpperCase() || 'USD';

  if (projectCode !== PROJECT_CODE) {
    return res.status(400).json({
      success: false,
      message: 'Este endpoint solo acepta project_code FULLCREDIT.',
    });
  }
  if (!businessId || !deviceId) {
    return res.status(400).json({
      success: false,
      message: 'business_id y device_id son requeridos.',
    });
  }
  if (!UUID_RE.test(paymentReference)) {
    return res.status(400).json({
      success: false,
      message: 'payment_reference debe ser un UUID válido.',
    });
  }
  if (publicToken.length < 32) {
    return res.status(400).json({
      success: false,
      message: 'payment_token debe contener al menos 32 caracteres.',
    });
  }
  if (!Number.isFinite(amount) || amount <= 0 || amount > 1000000) {
    return res.status(400).json({
      success: false,
      message: 'El monto del cobro no es válido.',
    });
  }

  const project = await model.findProject();
  if (!project) {
    return res.status(503).json({
      success: false,
      message: 'El proyecto FULLCREDIT no está activo en APYRA.',
    });
  }

  const currency = text(project.currency, 10).toUpperCase() || 'USD';
  if (requestedCurrency !== currency) {
    return res.status(400).json({
      success: false,
      message: `La moneda configurada para FULLCREDIT es ${currency}.`,
    });
  }

  const installationIsActive = await model.hasActiveInstallation({
    businessId,
    deviceId,
  });
  if (!installationIsActive) {
    return res.status(403).json({
      success: false,
      message:
        'La instalación FULLCREDIT no tiene una licencia activa para crear cobros.',
    });
  }

  const existing = await model.findByReference({
    businessId,
    paymentReference,
  });
  if (existing) {
    if (!tokenMatches(existing, publicToken)) {
      return res.status(409).json({
        success: false,
        message: 'La referencia de pago ya existe con otro token.',
      });
    }
    return res.json({
      success: true,
      idempotent: true,
      payment_token: publicToken,
      order: publicOrder(existing),
    });
  }

  let localOrder = await model.createOrder({
    projectId: project.id,
    businessId,
    deviceId,
    paymentReference,
    amount: Number(amount.toFixed(2)),
    currency,
    publicTokenHash: tokenHash(publicToken),
  });

  if (!localOrder) {
    localOrder = await model.findByReference({ businessId, paymentReference });
    if (!localOrder || !tokenMatches(localOrder, publicToken)) {
      return res.status(409).json({
        success: false,
        message: 'La referencia de pago ya existe con otro token.',
      });
    }
    return res.json({
      success: true,
      idempotent: true,
      payment_token: publicToken,
      order: publicOrder(localOrder),
    });
  }

  const baseUrl = publicBaseUrl(req);
  const returnUrl =
    `${baseUrl}/paypal/fullcredit/success` +
    `?payment_order_id=${encodeURIComponent(localOrder.id)}` +
    `&payment_token=${encodeURIComponent(publicToken)}`;
  const cancelUrl =
    `${baseUrl}/paypal/fullcredit/cancel` +
    `?payment_order_id=${encodeURIComponent(localOrder.id)}` +
    `&payment_token=${encodeURIComponent(publicToken)}`;

  try {
    const providerOrder = await paypalService.createOrder({
      amount: Number(localOrder.amount),
      currency,
      description: `${PROJECT_CODE} - Cobro ${paymentReference.slice(0, 8)}`,
      metadata: {
        payment_order_id: localOrder.id,
        invoice_id: `${PROJECT_CODE}-${paymentReference}`,
      },
      returnUrl,
      cancelUrl,
    });

    localOrder = await model.attachProviderOrder(localOrder.id, {
      providerOrderId: providerOrder.id,
      checkoutUrl: providerOrder.checkout_url,
      rawResponse: {
        provider_status: providerOrder.status,
        project_code: PROJECT_CODE,
      },
    });

    return res.status(201).json({
      success: true,
      payment_token: publicToken,
      order: publicOrder(localOrder),
    });
  } catch (error) {
    await model.updateStatus(localOrder.id, {
      status: 'FAILED',
      rawResponse: { create_error: error.message },
    });
    console.error('[fullcredit-card:create]', error);
    return res.status(502).json({
      success: false,
      message: 'PayPal no pudo crear la orden de cobro.',
    });
  }
}

async function captureOrder(req, res) {
  const id = text(req.body?.payment_order_id, 36);
  const paymentToken = text(req.body?.payment_token, 200);
  const order = await model.findById(id);

  if (!order || !tokenMatches(order, paymentToken)) {
    return res.status(404).json({
      success: false,
      message: 'Orden de cobro no encontrada.',
    });
  }
  if (order.status === 'PAID') {
    return res.json({
      success: true,
      idempotent: true,
      order: publicOrder(order),
    });
  }
  if (!order.provider_order_id) {
    return res.status(409).json({
      success: false,
      message: 'La orden todavía no está disponible en PayPal.',
    });
  }

  try {
    const capture = await paypalService.captureOrder(order.provider_order_id);
    const amountMatches =
      Math.abs(Number(capture.amount) - Number(order.amount)) < 0.005;
    const currencyMatches =
      text(capture.currency, 10).toUpperCase() ===
      text(order.currency, 10).toUpperCase();
    const completed =
      text(capture.status, 30).toUpperCase() === 'COMPLETED' &&
      Boolean(capture.capture_id);

    if (!completed || !amountMatches || !currencyMatches) {
      await model.updateStatus(order.id, {
        status: 'FAILED',
        rawResponse: {
          capture_status: capture.status,
          captured_amount: capture.amount,
          captured_currency: capture.currency,
          verification_failed: true,
        },
      });
      return res.status(409).json({
        success: false,
        message: 'PayPal no confirmó exactamente el monto esperado.',
      });
    }

    const paidOrder = await model.updateStatus(order.id, {
      status: 'PAID',
      providerCaptureId: capture.capture_id,
      paidAt: new Date(),
      rawResponse: {
        capture_status: capture.status,
        captured_amount: capture.amount,
        captured_currency: capture.currency,
      },
    });
    return res.json({ success: true, order: publicOrder(paidOrder) });
  } catch (error) {
    console.error('[fullcredit-card:capture]', error);
    return res.status(502).json({
      success: false,
      message: 'No se pudo confirmar el cobro con PayPal.',
    });
  }
}

async function status(req, res) {
  const id = text(req.params?.id, 36);
  const paymentToken = text(req.query?.payment_token, 200);
  let order = await model.findById(id);
  if (!order || !tokenMatches(order, paymentToken)) {
    return res.status(404).json({
      success: false,
      message: 'Orden de cobro no encontrada.',
    });
  }

  if (order.status !== 'PAID' && order.provider_order_id) {
    try {
      const providerOrder = await paypalService.verifyOrder(
        order.provider_order_id
      );
      const providerStatus = text(providerOrder.status, 30).toUpperCase();
      if (providerStatus === 'APPROVED') {
        order = await model.updateStatus(order.id, {
          status: 'APPROVED',
          rawResponse: { provider_status: providerStatus },
        });
      }
    } catch (error) {
      console.warn('[fullcredit-card:status]', error.message);
    }
  }

  return res.json({ success: true, order: publicOrder(order) });
}

async function cancelOrder(req, res) {
  const id = text(req.body?.payment_order_id, 36);
  const paymentToken = text(req.body?.payment_token, 200);
  const order = await model.findById(id);
  if (!order || !tokenMatches(order, paymentToken)) {
    return res.status(404).json({
      success: false,
      message: 'Orden de cobro no encontrada.',
    });
  }
  if (order.status === 'PAID') {
    return res.status(409).json({
      success: false,
      message: 'Un cobro confirmado no puede cancelarse.',
    });
  }
  const cancelled = await model.updateStatus(order.id, {
    status: 'CANCELLED',
    rawResponse: { cancelled_at: new Date().toISOString() },
  });
  return res.json({ success: true, order: publicOrder(cancelled) });
}

module.exports = {
  createOrder,
  captureOrder,
  status,
  cancelOrder,
  publicOrder,
  tokenMatches,
};
