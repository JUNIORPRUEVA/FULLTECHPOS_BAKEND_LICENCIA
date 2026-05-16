const { pool } = require('../db/pool');

const paypalModel = require('../models/paypalModel');
const productPlansModel = require('../models/productPlansModel');
const subscriptionsModel = require('../models/subscriptionsModel');
const paymentsModel = require('../models/paymentsModel');
const activationsModel = require('../models/activationsModel');
const projectsModel = require('../models/projectsModel');
const auditLogService = require('./auditLogService');
const paymentService = require('./paymentService');
const { generateLicenseKey } = require('../utils/licenseKey');

function paypalBaseUrl() {
  const mode = String(process.env.PAYPAL_MODE || process.env.PAYPAL_ENV || 'sandbox').trim().toLowerCase();
  return mode === 'live' || mode === 'production'
    ? 'https://api-m.paypal.com'
    : 'https://api-m.sandbox.paypal.com';
}

function requireFetch() {
  if (typeof fetch !== 'function') {
    throw httpError(500, 'FETCH_UNAVAILABLE', 'La versión de Node.js no tiene fetch global. Use Node 18+ para PayPal REST.');
  }
  return fetch;
}

function httpError(statusCode, code, message) {
  const error = new Error(message || code);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}

function normalizeUuid(value, fieldName = 'id') {
  const raw = String(value || '').trim();
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)) return raw;
  throw httpError(400, 'INVALID_UUID', `${fieldName} inválido`);
}

function optionalUuid(value) {
  const raw = String(value || '').trim();
  if (!raw) return null;
  return normalizeUuid(raw);
}

function moneyValue(value) {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount) || amount < 0) throw httpError(400, 'INVALID_AMOUNT', 'Monto inválido');
  return amount.toFixed(2);
}

function normalizeCurrency(value, fallback = 'USD') {
  const currency = String(value || fallback).trim().toUpperCase();
  return currency || fallback;
}

function getReturnUrl(payload) {
  return String(payload?.return_url || process.env.PAYPAL_RETURN_URL || process.env.PUBLIC_APP_URL || '').trim() || 'https://example.com/paypal/success';
}

function getCancelUrl(payload) {
  return String(payload?.cancel_url || process.env.PAYPAL_CANCEL_URL || process.env.PUBLIC_APP_URL || '').trim() || 'https://example.com/paypal/cancel';
}

async function getAccessToken() {
  const clientId = String(process.env.PAYPAL_CLIENT_ID || '').trim();
  const secret = String(process.env.PAYPAL_CLIENT_SECRET || '').trim();
  if (!clientId || !secret) {
    throw httpError(500, 'PAYPAL_NOT_CONFIGURED', 'PAYPAL_CLIENT_ID y PAYPAL_CLIENT_SECRET son requeridos');
  }

  const response = await requireFetch()(`${paypalBaseUrl()}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${clientId}:${secret}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: 'grant_type=client_credentials'
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token) {
    throw httpError(502, 'PAYPAL_AUTH_FAILED', data.message || data.error_description || 'No se pudo autenticar con PayPal');
  }
  return data.access_token;
}

async function paypalRequest(method, path, body = null) {
  const token = await getAccessToken();
  const response = await requireFetch()(`${paypalBaseUrl()}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Accept: 'application/json'
    },
    body: body == null ? undefined : JSON.stringify(body)
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw httpError(response.status, 'PAYPAL_API_ERROR', data.message || data.name || 'Error en API PayPal');
  }
  return data;
}

async function ensureCompany(companyId, client) {
  const res = await client.query('SELECT id, name FROM companies WHERE id = $1', [companyId]);
  if (!res.rows[0]) throw httpError(404, 'COMPANY_NOT_FOUND', 'Compañía no encontrada');
  return res.rows[0];
}

async function ensureCustomer(customerId, client) {
  if (!customerId) return null;
  const res = await client.query('SELECT * FROM customers WHERE id = $1', [customerId]);
  if (!res.rows[0]) throw httpError(404, 'CUSTOMER_NOT_FOUND', 'Cliente no encontrado');
  return res.rows[0];
}

async function defaultProjectId() {
  const project = await projectsModel.getDefaultProject();
  if (!project) throw httpError(500, 'DEFAULT_PROJECT_NOT_FOUND', 'Proyecto predeterminado no encontrado');
  return project.id;
}

async function createLicenseForPlan({ companyId, customerId, subscriptionId, plan, licenseType, client }) {
  const projectId = plan.project_id || await defaultProjectId();
  const productId = plan.product_id || null;
  const days = licenseType === 'PERMANENTE' ? 36500 : 31;

  for (let attempt = 0; attempt < 8; attempt++) {
    const key = generateLicenseKey('FULL');
    try {
      const res = await client.query(
        `INSERT INTO licenses (
          project_id, customer_id, license_key, tipo, license_type, dias_validez,
          max_dispositivos, estado, notas, company_id, subscription_id, product_id,
          issued_at, fecha_inicio, fecha_fin, expires_at
        ) VALUES (
          $1,$2,$3,'FULL',$4,$5,$6,'ACTIVA',$7,$8,$9,$10,now(),now(),$11,$11
        ) RETURNING *`,
        [
          projectId,
          customerId || null,
          key,
          licenseType,
          days,
          Number(plan.device_limit || 1),
          `Licencia creada automáticamente por PayPal (${licenseType})`,
          companyId,
          subscriptionId || null,
          productId,
          licenseType === 'PERMANENTE' ? null : new Date(Date.now() + days * 24 * 60 * 60 * 1000)
        ]
      );
      return res.rows[0];
    } catch (error) {
      if (error?.code === '23505') continue;
      throw error;
    }
  }

  throw httpError(500, 'LICENSE_KEY_GENERATION_FAILED', 'No se pudo generar una licencia única');
}

async function createPayPalProductAndPlan(plan, { client }) {
  if (plan.paypal_plan_id) return plan;
  if (!['monthly', 'annual'].includes(plan.billing_period)) {
    throw httpError(400, 'PAYPAL_PLAN_UNSUPPORTED', 'Solo planes mensuales o anuales usan suscripción PayPal');
  }

  let paypalProductId = plan.paypal_product_id;
  if (!paypalProductId) {
    const product = await paypalRequest('POST', '/v1/catalogs/products', {
      name: plan.product_name || plan.project_name || 'FULLTECH POS SaaS',
      description: `Producto SaaS para ${plan.name}`,
      type: 'SERVICE',
      category: 'SOFTWARE'
    });
    paypalProductId = product.id;
  }

  const intervalUnit = plan.billing_period === 'annual' ? 'YEAR' : 'MONTH';
  const paypalPlan = await paypalRequest('POST', '/v1/billing/plans', {
    product_id: paypalProductId,
    name: plan.name,
    description: `${plan.name} (${plan.billing_period})`,
    status: 'ACTIVE',
    billing_cycles: [
      {
        frequency: { interval_unit: intervalUnit, interval_count: 1 },
        tenure_type: 'REGULAR',
        sequence: 1,
        total_cycles: 0,
        pricing_scheme: {
          fixed_price: {
            value: moneyValue(plan.price_amount),
            currency_code: normalizeCurrency(plan.currency)
          }
        }
      }
    ],
    payment_preferences: {
      auto_bill_outstanding: true,
      setup_fee_failure_action: 'CONTINUE',
      payment_failure_threshold: 1
    }
  });

  return productPlansModel.updatePayPalIds(plan.id, {
    paypal_product_id: paypalProductId,
    paypal_plan_id: paypalPlan.id
  }, { client });
}

function approvalUrlFromLinks(links = []) {
  const approval = links.find((link) => link.rel === 'approve' || link.rel === 'payer-action');
  return approval?.href || null;
}

async function createOrder(payload, { req } = {}) {
  const companyId = normalizeUuid(payload.company_id, 'company_id');
  const customerId = optionalUuid(payload.customer_id);
  const planId = normalizeUuid(payload.plan_id, 'plan_id');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await ensureCompany(companyId, client);
    await ensureCustomer(customerId, client);
    const plan = await productPlansModel.getById(planId, { client });
    if (!plan) throw httpError(404, 'PLAN_NOT_FOUND', 'Plan no encontrado');
    if (plan.billing_period !== 'lifetime') {
      throw httpError(400, 'PLAN_NOT_ONE_TIME', 'Los pagos únicos requieren un plan lifetime/permanente');
    }

    const localOrder = await paypalModel.createOrder({
      order_type: 'ONE_TIME',
      company_id: companyId,
      customer_id: customerId,
      plan_id: plan.id,
      product_id: plan.product_id,
      project_id: plan.project_id,
      amount: plan.price_amount,
      currency: normalizeCurrency(plan.currency),
      request_payload: payload
    }, { client });

    const paypalOrder = await paypalRequest('POST', '/v2/checkout/orders', {
      intent: 'CAPTURE',
      purchase_units: [
        {
          reference_id: localOrder.id,
          custom_id: localOrder.id,
          description: `${plan.name} - licencia permanente`,
          amount: {
            currency_code: normalizeCurrency(plan.currency),
            value: moneyValue(plan.price_amount)
          }
        }
      ],
      application_context: {
        brand_name: process.env.PAYPAL_BRAND_NAME || 'FULLTECH POS',
        landing_page: 'NO_PREFERENCE',
        user_action: 'PAY_NOW',
        return_url: getReturnUrl(payload),
        cancel_url: getCancelUrl(payload)
      }
    });

    const approvalUrl = approvalUrlFromLinks(paypalOrder.links || []);
    await paypalModel.updateOrderById(localOrder.id, {
      paypal_order_id: paypalOrder.id,
      status: paypalOrder.status || 'CREATED',
      approval_url: approvalUrl,
      paypal_payload: paypalOrder
    }, { client });

    await auditLogService.log({
      company_id: companyId,
      product_id: plan.product_id,
      project_id: plan.project_id,
      target_type: 'payment',
      target_id: localOrder.id,
      action: 'paypal.order_create',
      after_data: { paypal_order_id: paypalOrder.id, plan_id: plan.id }
    }, { client, req });

    await client.query('COMMIT');
    return { paypal_order_id: paypalOrder.id, approval_url: approvalUrl, status: paypalOrder.status };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function completeOneTimeOrder(paypalOrderId, paypalPayload, { req } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const order = await paypalModel.getOrderByPayPalId(paypalOrderId, { client, forUpdate: true });
    if (!order) throw httpError(404, 'ORDER_NOT_FOUND', 'Orden PayPal no encontrada localmente');
    if (order.status === 'COMPLETED' && order.license_id) {
      await client.query('COMMIT');
      return { order, idempotent: true };
    }

    const plan = await productPlansModel.getById(order.plan_id, { client });
    if (!plan) throw httpError(404, 'PLAN_NOT_FOUND', 'Plan no encontrado');

    const subscription = await subscriptionsModel.create({
      company_id: order.company_id,
      customer_id: order.customer_id,
      product_id: order.product_id,
      project_id: order.project_id,
      plan_id: plan.id,
      amount: order.amount,
      next_payment_date: null,
      license_type: 'PERMANENTE',
      status: 'ACTIVE',
      start_date: new Date(),
      end_date: null,
      renewal_date: null,
      notes: 'Suscripción local creada por pago único PayPal',
      metadata: { paypal_order_id: paypalOrderId }
    }, { client });

    const license = await createLicenseForPlan({
      companyId: order.company_id,
      customerId: order.customer_id,
      subscriptionId: subscription.id,
      plan,
      licenseType: 'PERMANENTE',
      client
    });

    const capture = paypalPayload.purchase_units?.[0]?.payments?.captures?.[0] || {};
    const payment = await paymentsModel.create({
      company_id: order.company_id,
      subscription_id: subscription.id,
      product_id: order.product_id,
      project_id: order.project_id,
      license_id: license.id,
      amount: Number(capture.amount?.value || order.amount),
      currency: capture.amount?.currency_code || order.currency,
      status: 'paid',
      payment_method: 'paypal',
      reference: capture.id || paypalOrderId,
      paid_at: capture.create_time ? new Date(capture.create_time) : new Date(),
      gateway_payload: paypalPayload,
      paypal_order_id: paypalOrderId,
      paypal_capture_id: capture.id || null
    }, { client });

    await paymentService.applyPaidPaymentEffects({ subscription, payment, plan, client, req });

    const updatedOrder = await paypalModel.updateOrderById(order.id, {
      license_id: license.id,
      subscription_id: subscription.id,
      status: 'COMPLETED',
      paypal_payload: paypalPayload,
      captured_at: new Date()
    }, { client });

    await client.query('COMMIT');
    return { order: updatedOrder, license, subscription, payment, idempotent: false };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function captureOrder(payload, { req } = {}) {
  const paypalOrderId = String(payload?.paypal_order_id || payload?.order_id || '').trim();
  if (!paypalOrderId) throw httpError(400, 'PAYPAL_ORDER_REQUIRED', 'paypal_order_id es requerido');

  const existing = await paypalModel.getOrderByPayPalId(paypalOrderId);
  if (existing?.status === 'COMPLETED' && existing.license_id) {
    return { ok: true, idempotent: true, license_id: existing.license_id, subscription_id: existing.subscription_id };
  }

  const captured = await paypalRequest('POST', `/v2/checkout/orders/${encodeURIComponent(paypalOrderId)}/capture`, {});
  if (captured.status !== 'COMPLETED') {
    throw httpError(402, 'PAYPAL_ORDER_NOT_COMPLETED', 'PayPal no confirmó el pago');
  }

  const result = await completeOneTimeOrder(paypalOrderId, captured, { req });
  return {
    ok: true,
    idempotent: result.idempotent,
    license: result.license || null,
    subscription: result.subscription || null,
    payment: result.payment || null
  };
}

async function createSubscription(payload, { req } = {}) {
  const companyId = normalizeUuid(payload.company_id, 'company_id');
  const customerId = optionalUuid(payload.customer_id);
  const planId = normalizeUuid(payload.plan_id, 'plan_id');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await ensureCompany(companyId, client);
    await ensureCustomer(customerId, client);
    let plan = await productPlansModel.getById(planId, { client });
    if (!plan) throw httpError(404, 'PLAN_NOT_FOUND', 'Plan no encontrado');
    if (!['monthly', 'annual'].includes(plan.billing_period)) {
      throw httpError(400, 'PLAN_NOT_RECURRING', 'Solo planes mensuales o anuales usan suscripción automática');
    }

    plan = await createPayPalProductAndPlan(plan, { client });

    const localSubscription = await subscriptionsModel.create({
      company_id: companyId,
      customer_id: customerId,
      product_id: plan.product_id,
      project_id: plan.project_id,
      plan_id: plan.id,
      amount: plan.price_amount,
      next_payment_date: null,
      license_type: 'SUSCRIPCION',
      status: 'PENDING_PAYMENT',
      start_date: new Date(),
      notes: 'Suscripción creada desde PayPal, pendiente de confirmación',
      metadata: { paypal_plan_id: plan.paypal_plan_id }
    }, { client });

    const paypalSubscription = await paypalRequest('POST', '/v1/billing/subscriptions', {
      plan_id: plan.paypal_plan_id,
      custom_id: localSubscription.id,
      quantity: '1',
      application_context: {
        brand_name: process.env.PAYPAL_BRAND_NAME || 'FULLTECH POS',
        user_action: 'SUBSCRIBE_NOW',
        return_url: getReturnUrl(payload),
        cancel_url: getCancelUrl(payload)
      }
    });

    const updatedSubscription = await subscriptionsModel.updateById(localSubscription.id, {
      paypal_subscription_id: paypalSubscription.id,
      metadata: { ...(localSubscription.metadata || {}), paypal_subscription: paypalSubscription }
    }, { client });

    await auditLogService.log({
      company_id: companyId,
      product_id: plan.product_id,
      project_id: plan.project_id,
      target_type: 'subscription',
      target_id: updatedSubscription.id,
      action: 'paypal.subscription_create',
      after_data: { paypal_subscription_id: paypalSubscription.id, plan_id: plan.id }
    }, { client, req });

    await client.query('COMMIT');
    return {
      subscription: updatedSubscription,
      paypal_subscription_id: paypalSubscription.id,
      approval_url: approvalUrlFromLinks(paypalSubscription.links || []),
      status: paypalSubscription.status
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function verifyWebhook(headers, event) {
  const webhookId = String(process.env.PAYPAL_WEBHOOK_ID || '').trim();
  if (!webhookId) throw httpError(500, 'PAYPAL_WEBHOOK_NOT_CONFIGURED', 'PAYPAL_WEBHOOK_ID es requerido para validar webhooks');

  const verification = await paypalRequest('POST', '/v1/notifications/verify-webhook-signature', {
    auth_algo: headers['paypal-auth-algo'],
    cert_url: headers['paypal-cert-url'],
    transmission_id: headers['paypal-transmission-id'],
    transmission_sig: headers['paypal-transmission-sig'],
    transmission_time: headers['paypal-transmission-time'],
    webhook_id: webhookId,
    webhook_event: event
  });

  if (verification.verification_status !== 'SUCCESS') {
    throw httpError(401, 'PAYPAL_WEBHOOK_INVALID', 'Firma de webhook PayPal inválida');
  }
  return true;
}

function nextBillingDateFromResource(resource) {
  const value = resource?.billing_info?.next_billing_time || resource?.next_billing_time;
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

async function ensureSubscriptionLicense(subscription, plan, client) {
  if (subscription.license_id) return subscription;
  const license = await createLicenseForPlan({
    companyId: subscription.company_id,
    customerId: subscription.customer_id,
    subscriptionId: subscription.id,
    plan,
    licenseType: 'SUSCRIPCION',
    client
  });
  return subscriptionsModel.updateById(subscription.id, {
    license_id: license.id,
    customer_id: subscription.customer_id || license.customer_id || null
  }, { client });
}

async function handleSubscriptionActivated(event, { client, req }) {
  const resource = event.resource || {};
  const paypalSubscriptionId = resource.id;
  let subscription = await subscriptionsModel.findByPayPalSubscriptionId(paypalSubscriptionId, { client, forUpdate: true });
  if (!subscription && resource.custom_id) {
    subscription = await subscriptionsModel.getByIdForUpdate(resource.custom_id, { client });
  }
  if (!subscription) throw httpError(404, 'LOCAL_SUBSCRIPTION_NOT_FOUND', 'Suscripción local no encontrada');

  const nextPaymentDate = nextBillingDateFromResource(resource) || subscription.next_payment_date;
  const updated = await subscriptionsModel.updateById(subscription.id, {
    status: 'ACTIVE',
    paypal_subscription_id: paypalSubscriptionId,
    next_payment_date: nextPaymentDate,
    renewal_date: nextPaymentDate,
    end_date: nextPaymentDate,
    metadata: { ...(subscription.metadata || {}), paypal_last_event: event.event_type }
  }, { client });

  await auditLogService.log({
    company_id: updated.company_id,
    product_id: updated.product_id,
    project_id: updated.project_id,
    target_type: 'subscription',
    target_id: updated.id,
    action: 'paypal.subscription_activated',
    after_data: { paypal_subscription_id: paypalSubscriptionId, next_payment_date: nextPaymentDate }
  }, { client, req });

  return updated;
}

async function handleSaleCompleted(event, { client, req }) {
  const resource = event.resource || {};
  const paypalSubscriptionId = resource.billing_agreement_id || resource.billing_agreement?.id || resource.subscription_id;
  if (!paypalSubscriptionId) throw httpError(400, 'PAYPAL_SUBSCRIPTION_ID_MISSING', 'Evento sin billing_agreement_id');

  let subscription = await subscriptionsModel.findByPayPalSubscriptionId(paypalSubscriptionId, { client, forUpdate: true });
  if (!subscription) throw httpError(404, 'LOCAL_SUBSCRIPTION_NOT_FOUND', 'Suscripción local no encontrada');

  const existingPayment = await paymentsModel.findByReference(subscription.id, resource.id, { client, forUpdate: true });
  if (existingPayment) return { payment: existingPayment, subscription, idempotent: true };

  const plan = await productPlansModel.getById(subscription.plan_id, { client });
  if (!plan) throw httpError(404, 'PLAN_NOT_FOUND', 'Plan no encontrado');
  subscription = await ensureSubscriptionLicense(subscription, plan, client);

  const amount = Number(resource.amount?.total || resource.amount?.value || subscription.amount || plan.price_amount || 0);
  const currency = resource.amount?.currency || resource.amount?.currency_code || plan.currency || 'USD';
  const payment = await paymentsModel.create({
    company_id: subscription.company_id,
    subscription_id: subscription.id,
    product_id: subscription.product_id,
    project_id: subscription.project_id,
    license_id: subscription.license_id,
    amount,
    currency,
    status: 'paid',
    payment_method: 'paypal',
    reference: resource.id,
    paid_at: resource.create_time ? new Date(resource.create_time) : new Date(),
    gateway_payload: event,
    paypal_subscription_id: paypalSubscriptionId,
    paypal_capture_id: resource.id
  }, { client });

  const sideEffects = await paymentService.applyPaidPaymentEffects({ subscription, payment, plan, client, req });
  return { payment, subscription: sideEffects.updatedSubscription, license: sideEffects.linkedLicense, idempotent: false };
}

async function handleSubscriptionCancelled(event, { client, req }) {
  const resource = event.resource || {};
  const paypalSubscriptionId = resource.id;
  const subscription = await subscriptionsModel.findByPayPalSubscriptionId(paypalSubscriptionId, { client, forUpdate: true });
  if (!subscription) throw httpError(404, 'LOCAL_SUBSCRIPTION_NOT_FOUND', 'Suscripción local no encontrada');

  const updated = await subscriptionsModel.updateById(subscription.id, {
    status: 'CANCELLED',
    cancelled_at: new Date(),
    metadata: { ...(subscription.metadata || {}), paypal_last_event: event.event_type }
  }, { client });

  if (updated.license_id) {
    await client.query(`UPDATE licenses SET estado = 'BLOQUEADA' WHERE id = $1`, [updated.license_id]);
    await activationsModel.blockActivationsForLicense(updated.license_id, { client });
  }

  await auditLogService.log({
    company_id: updated.company_id,
    product_id: updated.product_id,
    project_id: updated.project_id,
    target_type: 'subscription',
    target_id: updated.id,
    action: 'paypal.subscription_cancelled',
    after_data: { paypal_subscription_id: paypalSubscriptionId, status: updated.status }
  }, { client, req });

  return updated;
}

async function processWebhook(event, { req } = {}) {
  if (!event?.id || !event?.event_type) throw httpError(400, 'INVALID_WEBHOOK_EVENT', 'Evento PayPal inválido');
  await verifyWebhook(req.headers || {}, event);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const marker = await paypalModel.markWebhookProcessing(event, { client });
    if (!marker) {
      await client.query('COMMIT');
      return { ok: true, idempotent: true };
    }

    let result = null;
    if (event.event_type === 'BILLING.SUBSCRIPTION.ACTIVATED') {
      result = await handleSubscriptionActivated(event, { client, req });
    } else if (event.event_type === 'PAYMENT.SALE.COMPLETED') {
      result = await handleSaleCompleted(event, { client, req });
    } else if (event.event_type === 'BILLING.SUBSCRIPTION.CANCELLED') {
      result = await handleSubscriptionCancelled(event, { client, req });
    }

    await paypalModel.markWebhookProcessed(event.id, { status: 'processed' }, { client });
    await client.query('COMMIT');
    return { ok: true, event_type: event.event_type, processed: Boolean(result), result };
  } catch (error) {
    await client.query('ROLLBACK');
    const failClient = await pool.connect();
    try {
      await paypalModel.markWebhookProcessed(event.id, {
        status: 'failed',
        event_type: event.event_type,
        resource_id: event.resource?.id || event.resource?.billing_agreement_id || null,
        payload: event,
        error_message: String(error.message || error).slice(0, 1000)
      }, { client: failClient });
    } finally {
      failClient.release();
    }
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  createOrder,
  captureOrder,
  createSubscription,
  processWebhook,
  paypalRequest,
  httpError
};
