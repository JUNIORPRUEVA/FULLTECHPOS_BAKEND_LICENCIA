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
  const explicitBaseUrl = String(process.env.PAYPAL_BASE_URL || '').trim().replace(/\/+$/, '');
  if (explicitBaseUrl) return explicitBaseUrl;

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

function normalizeDescription(value) {
  const description = String(value || '').trim();
  if (!description) throw httpError(400, 'DESCRIPTION_REQUIRED', 'descripcion es requerida');
  return description.slice(0, 127);
}

async function resolvePlatformUserId(payload, req, client) {
  const explicit = payload?.user_id || payload?.usuario_id || req?.headers?.['x-user-id'];
  if (explicit) return normalizeUuid(explicit, 'user_id');

  const username = String(req?.adminUser || req?.user?.email || '').trim().toLowerCase();
  if (username) {
    const res = await client.query(
      `SELECT id FROM platform_users
       WHERE lower(email) = $1 OR lower(COALESCE(display_name, '')) = $1
       LIMIT 1`,
      [username]
    );
    if (res.rows[0]) return res.rows[0].id;
  }

  throw httpError(401, 'USER_ID_REQUIRED', 'No se pudo identificar el usuario para el pago');
}

function getReturnUrl(payload) {
  return String(payload?.return_url || process.env.PAYPAL_RETURN_URL || process.env.PUBLIC_APP_URL || '').trim() || 'https://example.com/paypal/success';
}

function getCancelUrl(payload) {
  return String(payload?.cancel_url || process.env.PAYPAL_CANCEL_URL || process.env.PUBLIC_APP_URL || '').trim() || 'https://example.com/paypal/cancel';
}

async function getAccessToken() {
  const clientId = String(process.env.PAYPAL_CLIENT_ID || '').trim();
  const secret = String(process.env.PAYPAL_SECRET || process.env.PAYPAL_CLIENT_SECRET || '').trim();
  if (!clientId || !secret) {
    throw httpError(500, 'PAYPAL_NOT_CONFIGURED', 'PAYPAL_CLIENT_ID y PAYPAL_SECRET son requeridos');
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

function saasBillingPeriod(planType) {
  if (planType === 'mensual') return 'MONTH';
  if (planType === 'anual') return 'YEAR';
  throw httpError(400, 'PLAN_NOT_RECURRING', 'Solo planes mensuales o anuales usan suscripción automática');
}

async function getSaasPlanById(planId, { client, forUpdate = false } = {}) {
  const res = await client.query(
    `SELECT * FROM saas_planes WHERE id = $1${forUpdate ? ' FOR UPDATE' : ''}`,
    [planId]
  );
  return res.rows[0] || null;
}

async function createPayPalProductAndSaasPlan(plan, { client }) {
  if (plan.paypal_plan_id) return plan;
  const intervalUnit = saasBillingPeriod(plan.tipo);

  let paypalProductId = plan.paypal_product_id;
  if (!paypalProductId) {
    const product = await paypalRequest('POST', '/v1/catalogs/products', {
      name: process.env.PAYPAL_BRAND_NAME || 'FULLTECH POS SaaS',
      description: `Producto SaaS para ${plan.nombre}`,
      type: 'SERVICE',
      category: 'SOFTWARE'
    });
    paypalProductId = product.id;
  }

  const paypalPlan = await paypalRequest('POST', '/v1/billing/plans', {
    product_id: paypalProductId,
    name: plan.nombre,
    description: `${plan.nombre} (${plan.tipo})`,
    status: 'ACTIVE',
    billing_cycles: [
      {
        frequency: { interval_unit: intervalUnit, interval_count: 1 },
        tenure_type: 'REGULAR',
        sequence: 1,
        total_cycles: 0,
        pricing_scheme: {
          fixed_price: {
            value: moneyValue(plan.precio),
            currency_code: normalizeCurrency(plan.moneda)
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

  const updated = await client.query(
    `UPDATE saas_planes
     SET paypal_product_id = $2,
         paypal_plan_id = $3,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [plan.id, paypalProductId, paypalPlan.id]
  );
  return updated.rows[0];
}

async function syncPlanToPayPal(planId, { req } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const plan = await productPlansModel.getById(planId, { client });
    if (!plan) throw httpError(404, 'PLAN_NOT_FOUND', 'Plan no encontrado');
    if (!['monthly', 'annual'].includes(plan.billing_period)) {
      throw httpError(400, 'PAYPAL_PLAN_UNSUPPORTED', 'Solo planes mensuales o anuales se sincronizan con PayPal');
    }

    const syncedPlan = await createPayPalProductAndPlan(plan, { client });

    await auditLogService.log({
      product_id: syncedPlan.product_id,
      project_id: syncedPlan.project_id,
      target_type: 'plan',
      target_id: syncedPlan.id,
      action: 'paypal.plan_sync',
      after_data: {
        paypal_product_id: syncedPlan.paypal_product_id,
        paypal_plan_id: syncedPlan.paypal_plan_id,
        billing_period: syncedPlan.billing_period,
        price_amount: syncedPlan.price_amount,
        currency: syncedPlan.currency
      }
    }, { client, req });

    await client.query('COMMIT');
    return syncedPlan;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function syncRecurringPlansToPayPal({ req } = {}) {
  const { plans } = await productPlansModel.list({ is_active: true, limit: 500, offset: 0 });
  const recurringPlans = plans.filter((plan) => ['monthly', 'annual'].includes(plan.billing_period));
  const synced = [];
  const skipped = [];

  for (const plan of recurringPlans) {
    try {
      const syncedPlan = await syncPlanToPayPal(plan.id, { req });
      synced.push(syncedPlan);
    } catch (error) {
      skipped.push({ id: plan.id, name: plan.name, reason: error.message || String(error) });
    }
  }

  return { synced, skipped, total: recurringPlans.length };
}

function approvalUrlFromLinks(links = []) {
  const approval = links.find((link) => link.rel === 'approve' || link.rel === 'payer-action');
  return approval?.href || null;
}

async function createDirectOrder(payload, { req } = {}) {
  const amount = payload?.amount ?? payload?.monto;
  const description = normalizeDescription(payload?.description ?? payload?.descripcion);
  const currency = normalizeCurrency(payload?.currency ?? payload?.moneda, 'USD');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const userId = await resolvePlatformUserId(payload, req, client);

    const localOrder = await paypalModel.createOrder({
      order_type: 'ONE_TIME',
      user_id: userId,
      amount: moneyValue(amount),
      currency,
      status: 'pendiente',
      description,
      request_payload: payload
    }, { client });

    const paypalOrder = await paypalRequest('POST', '/v2/checkout/orders', {
      intent: 'CAPTURE',
      purchase_units: [
        {
          reference_id: localOrder.id,
          custom_id: localOrder.id,
          description,
          amount: {
            currency_code: currency,
            value: moneyValue(amount)
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
    const order = await paypalModel.updateOrderById(localOrder.id, {
      paypal_order_id: paypalOrder.id,
      status: 'pendiente',
      approval_url: approvalUrl,
      paypal_payload: paypalOrder
    }, { client });

    await auditLogService.log({
      target_type: 'payment',
      target_id: order.id,
      action: 'paypal.order_create',
      after_data: {
        paypal_order_id: paypalOrder.id,
        status: 'pendiente',
        amount: order.amount,
        currency: order.currency
      }
    }, { client, req });

    await client.query('COMMIT');
    return {
      paypal_order_id: paypalOrder.id,
      approval_url: approvalUrl,
      estado: 'pendiente',
      status: 'pendiente'
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function createUserSaasPlanOrder(payload, { req } = {}) {
  const planId = normalizeUuid(payload.plan_id, 'plan_id');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const userId = await resolvePlatformUserId(payload, req, client);
    const plan = await getSaasPlanById(planId, { client, forUpdate: true });
    if (!plan) throw httpError(404, 'PLAN_NOT_FOUND', 'Plan no encontrado');
    if (!plan.activo) throw httpError(400, 'PLAN_INACTIVE', 'El plan no está activo');
    if (plan.tipo !== 'permanente') {
      throw httpError(400, 'PLAN_NOT_ONE_TIME', 'Los pagos únicos requieren un plan permanente');
    }

    const description = `${plan.nombre} - licencia permanente`;
    const currency = normalizeCurrency(plan.moneda);
    const localOrder = await paypalModel.createOrder({
      order_type: 'ONE_TIME',
      user_id: userId,
      amount: moneyValue(plan.precio),
      currency,
      status: 'pendiente',
      description,
      request_payload: { ...payload, user_id: userId, saas_plan_id: plan.id }
    }, { client });

    const paypalOrder = await paypalRequest('POST', '/v2/checkout/orders', {
      intent: 'CAPTURE',
      purchase_units: [
        {
          reference_id: localOrder.id,
          custom_id: localOrder.id,
          description,
          amount: { currency_code: currency, value: moneyValue(plan.precio) }
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
    const order = await paypalModel.updateOrderById(localOrder.id, {
      paypal_order_id: paypalOrder.id,
      status: 'pendiente',
      approval_url: approvalUrl,
      paypal_payload: paypalOrder
    }, { client });

    await auditLogService.log({
      target_type: 'payment',
      target_id: order.id,
      action: 'paypal.saas_order_create',
      after_data: {
        user_id: userId,
        saas_plan_id: plan.id,
        paypal_order_id: paypalOrder.id,
        amount: order.amount,
        currency: order.currency
      }
    }, { client, req });

    await client.query('COMMIT');
    return {
      paypal_order_id: paypalOrder.id,
      approval_url: approvalUrl,
      estado: 'pendiente',
      status: 'pendiente'
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function createOrder(payload, { req } = {}) {
  if (payload?.plan_id && !payload?.company_id) {
    return createUserSaasPlanOrder(payload, { req });
  }

  if (!payload?.plan_id && (payload?.amount != null || payload?.monto != null)) {
    return createDirectOrder(payload, { req });
  }

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
      status: 'pendiente',
      description: `${plan.name} - licencia permanente`,
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
      status: 'pendiente',
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
    return { paypal_order_id: paypalOrder.id, approval_url: approvalUrl, estado: 'pendiente', status: 'pendiente' };
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

async function createPermanentSaasLicense({ userId, order, paypalPayload, client }) {
  const existingPayment = await client.query(
    `SELECT p.*, l.id AS existing_license_id
     FROM saas_pagos p
     LEFT JOIN saas_licencias l ON l.id = p.licencia_id
     WHERE p.paypal_order_id = $1
     LIMIT 1`,
    [order.paypal_order_id]
  );
  if (existingPayment.rows[0]?.existing_license_id) {
    return { payment: existingPayment.rows[0], license_id: existingPayment.rows[0].existing_license_id, idempotent: true };
  }

  const userRes = await client.query('SELECT id FROM platform_users WHERE id = $1 FOR UPDATE', [userId]);
  if (!userRes.rows[0]) throw httpError(404, 'USER_NOT_FOUND', 'Usuario no encontrado');

  const capture = paypalPayload.purchase_units?.[0]?.payments?.captures?.[0] || {};
  const paidAt = capture.create_time ? new Date(capture.create_time) : new Date();
  const amount = Number(capture.amount?.value || order.amount);
  const currency = capture.amount?.currency_code || order.currency || 'USD';

  let license = null;
  const saasPlanId = order.request_payload?.saas_plan_id || order.request_payload?.plan_id || null;
  for (let attempt = 0; attempt < 8; attempt++) {
    const licenseKey = generateLicenseKey('FULL');
    try {
      const licenseRes = await client.query(
        `INSERT INTO saas_licencias (
           user_id, plan_id, tipo, estado, fecha_activacion, fecha_expiracion, license_key, metadata
         ) VALUES ($1,$2,'permanente','activa',$3,NULL,$4,$5)
         RETURNING *`,
        [
          userId,
          saasPlanId,
          paidAt,
          licenseKey,
          {
            source: 'paypal_capture',
            paypal_order_id: order.paypal_order_id,
            description: order.description || null
          }
        ]
      );
      license = licenseRes.rows[0];
      break;
    } catch (error) {
      if (error?.code === '23505') continue;
      throw error;
    }
  }
  if (!license) throw httpError(500, 'LICENSE_KEY_GENERATION_FAILED', 'No se pudo generar la licencia permanente');

  const paymentRes = await client.query(
    `INSERT INTO saas_pagos (
       user_id, licencia_id, tipo, paypal_order_id, paypal_payment_id,
       monto, moneda, estado, fecha_pago, paypal_payload, metadata
     ) VALUES ($1,$2,'paypal',$3,$4,$5,$6,'completado',$7,$8,$9)
     ON CONFLICT (paypal_order_id) DO UPDATE
     SET licencia_id = EXCLUDED.licencia_id,
         paypal_payment_id = EXCLUDED.paypal_payment_id,
         monto = EXCLUDED.monto,
         moneda = EXCLUDED.moneda,
         estado = 'completado',
         fecha_pago = EXCLUDED.fecha_pago,
         paypal_payload = EXCLUDED.paypal_payload,
         updated_at = now()
     RETURNING *`,
    [
      userId,
      license.id,
      order.paypal_order_id,
      capture.id || null,
      amount,
      currency,
      paidAt,
      paypalPayload,
      { description: order.description || null }
    ]
  );

  await client.query(
    `UPDATE platform_users
     SET status = 'active', updated_at = now()
     WHERE id = $1`,
    [userId]
  );

  return { payment: paymentRes.rows[0], license, idempotent: false };
}

async function completeDirectOrder(paypalOrderId, paypalPayload, { req } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const order = await paypalModel.getOrderByPayPalId(paypalOrderId, { client, forUpdate: true });
    if (!order) throw httpError(404, 'ORDER_NOT_FOUND', 'Orden PayPal no encontrada localmente');

    if (order.status === 'completado') {
      await client.query('COMMIT');
      return { order, idempotent: true };
    }

    const userId = order.user_id || order.request_payload?.user_id;
    if (!userId) throw httpError(400, 'USER_ID_REQUIRED', 'La orden no tiene user_id para activar el usuario');

    const result = await createPermanentSaasLicense({ userId, order, paypalPayload, client });
    const updatedOrder = await paypalModel.updateOrderById(order.id, {
      status: 'completado',
      paypal_payload: paypalPayload,
      captured_at: new Date()
    }, { client });

    await auditLogService.log({
      target_type: 'payment',
      target_id: result.payment?.id || order.id,
      action: 'paypal.order_capture_completed',
      after_data: {
        paypal_order_id: paypalOrderId,
        payment_id: result.payment?.paypal_payment_id || null,
        license_id: result.license?.id || result.license_id || null,
        user_id: userId
      }
    }, { client, req });

    await client.query('COMMIT');
    return { order: updatedOrder, ...result };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function markDirectOrderFailed(paypalOrderId, paypalPayload, reason, { req } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const order = await paypalModel.getOrderByPayPalId(paypalOrderId, { client, forUpdate: true });
    if (!order) {
      await client.query('COMMIT');
      return null;
    }

    await paypalModel.updateOrderById(order.id, {
      status: 'fallido',
      paypal_payload: paypalPayload || { error: reason }
    }, { client });

    const userId = order.user_id || order.request_payload?.user_id || null;
    if (userId) {
      await client.query(
        `INSERT INTO saas_pagos (
           user_id, tipo, paypal_order_id, monto, moneda, estado, paypal_payload, metadata
         ) VALUES ($1,'paypal',$2,$3,$4,'fallido',$5,$6)
         ON CONFLICT (paypal_order_id) DO UPDATE
         SET estado = 'fallido',
             paypal_payload = EXCLUDED.paypal_payload,
             metadata = EXCLUDED.metadata,
             updated_at = now()`,
        [
          userId,
          order.paypal_order_id,
          order.amount,
          order.currency || 'USD',
          paypalPayload || {},
          { reason: String(reason || 'PayPal capture failed').slice(0, 500) }
        ]
      );
    }

    await auditLogService.log({
      target_type: 'payment',
      target_id: order.id,
      action: 'paypal.order_capture_failed',
      after_data: { paypal_order_id: paypalOrderId, reason }
    }, { client, req });

    await client.query('COMMIT');
    return order;
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
  if (existing?.status === 'completado') {
    return { ok: true, idempotent: true, order: existing };
  }
  if (existing?.status === 'COMPLETED' && existing.license_id) {
    return { ok: true, idempotent: true, license_id: existing.license_id, subscription_id: existing.subscription_id };
  }

  let captured = null;
  try {
    captured = await paypalRequest('POST', `/v2/checkout/orders/${encodeURIComponent(paypalOrderId)}/capture`, {});
  } catch (error) {
    await markDirectOrderFailed(paypalOrderId, { error: error.message || String(error) }, error.message || error, { req });
    throw error;
  }

  if (captured.status !== 'COMPLETED') {
    await markDirectOrderFailed(paypalOrderId, captured, `PayPal status: ${captured.status}`, { req });
    throw httpError(402, 'PAYPAL_ORDER_NOT_COMPLETED', 'PayPal no confirmó el pago');
  }

  const result = existing?.plan_id
    ? await completeOneTimeOrder(paypalOrderId, captured, { req })
    : await completeDirectOrder(paypalOrderId, captured, { req });
  return {
    ok: true,
    idempotent: result.idempotent,
    license: result.license || null,
    subscription: result.subscription || null,
    payment: result.payment || null,
    order: result.order || null,
    user_activated: Boolean(result.license || result.license_id)
  };
}

async function getPaymentStatus(payload = {}, { req } = {}) {
  const orderId = String(payload.order_id || payload.paypal_order_id || '').trim();
  const subscriptionId = String(payload.subscription_id || payload.paypal_subscription_id || '').trim();
  if (!orderId && !subscriptionId) {
    throw httpError(400, 'PAYPAL_STATUS_ID_REQUIRED', 'order_id o subscription_id es requerido');
  }

  const client = await pool.connect();
  try {
    if (orderId) {
      const order = await paypalModel.getOrderByPayPalId(orderId, { client });
      if (!order) throw httpError(404, 'ORDER_NOT_FOUND', 'Orden no encontrada');
      return {
        type: 'order',
        paypal_order_id: order.paypal_order_id,
        estado: order.status,
        status: order.status,
        paid: ['completado', 'COMPLETED'].includes(String(order.status)),
        license_id: order.license_id || null,
        subscription_id: order.subscription_id || null
      };
    }

    const saasSubscription = await findSaasSubscription({
      paypalSubscriptionId: subscriptionId,
      client
    });
    if (saasSubscription) {
      return {
        type: 'subscription',
        paypal_subscription_id: subscriptionId,
        estado: saasSubscription.estado,
        status: saasSubscription.estado,
        paid: saasSubscription.estado === 'activa',
        subscription: saasSubscription
      };
    }

    const subscription = await subscriptionsModel.findByPayPalSubscriptionId(subscriptionId, { client });
    if (!subscription) throw httpError(404, 'SUBSCRIPTION_NOT_FOUND', 'Suscripción no encontrada');
    return {
      type: 'subscription',
      paypal_subscription_id: subscriptionId,
      estado: subscription.status,
      status: subscription.status,
      paid: String(subscription.status).toUpperCase() === 'ACTIVE',
      subscription
    };
  } finally {
    client.release();
  }
}

async function createUserSaasSubscription(payload, { req } = {}) {
  const planId = normalizeUuid(payload.plan_id, 'plan_id');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const userId = await resolvePlatformUserId(payload, req, client);

    const userRes = await client.query('SELECT id, email, full_name FROM platform_users WHERE id = $1 FOR UPDATE', [userId]);
    if (!userRes.rows[0]) throw httpError(404, 'USER_NOT_FOUND', 'Usuario no encontrado');

    let plan = await getSaasPlanById(planId, { client, forUpdate: true });
    if (!plan) throw httpError(404, 'PLAN_NOT_FOUND', 'Plan no encontrado');
    if (!plan.activo) throw httpError(400, 'PLAN_INACTIVE', 'El plan no está activo');
    if (!['mensual', 'anual'].includes(plan.tipo)) {
      throw httpError(400, 'PLAN_NOT_RECURRING', 'Solo planes mensuales o anuales usan suscripción automática');
    }

    plan = await createPayPalProductAndSaasPlan(plan, { client });

    const localSubscriptionRes = await client.query(
      `INSERT INTO saas_suscripciones (
         user_id, plan_id, estado, fecha_inicio, metadata
       ) VALUES ($1,$2,'pendiente',now(),$3)
       RETURNING *`,
      [
        userId,
        plan.id,
        {
          source: 'paypal_create_subscription',
          paypal_plan_id: plan.paypal_plan_id,
          request_payload: payload
        }
      ]
    );
    const localSubscription = localSubscriptionRes.rows[0];

    const paypalSubscription = await paypalRequest('POST', '/v1/billing/subscriptions', {
      plan_id: plan.paypal_plan_id,
      custom_id: localSubscription.id,
      quantity: '1',
      subscriber: userRes.rows[0].email
        ? {
            email_address: userRes.rows[0].email,
            name: userRes.rows[0].full_name ? { given_name: userRes.rows[0].full_name } : undefined
          }
        : undefined,
      application_context: {
        brand_name: process.env.PAYPAL_BRAND_NAME || 'FULLTECH POS',
        user_action: 'SUBSCRIBE_NOW',
        return_url: getReturnUrl(payload),
        cancel_url: getCancelUrl(payload)
      }
    });

    const updatedSubscriptionRes = await client.query(
      `UPDATE saas_suscripciones
       SET paypal_subscription_id = $2,
           estado = 'pendiente',
           metadata = metadata || $3::jsonb,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [
        localSubscription.id,
        paypalSubscription.id,
        JSON.stringify({ paypal_subscription: paypalSubscription })
      ]
    );
    const subscription = updatedSubscriptionRes.rows[0];

    await client.query(
      `INSERT INTO saas_pagos (
         user_id, suscripcion_id, tipo, paypal_subscription_id,
         monto, moneda, estado, paypal_payload, metadata
       ) VALUES ($1,$2,'paypal',$3,$4,$5,'pendiente',$6,$7)`,
      [
        userId,
        subscription.id,
        paypalSubscription.id,
        plan.precio,
        normalizeCurrency(plan.moneda),
        paypalSubscription,
        { plan_id: plan.id, paypal_plan_id: plan.paypal_plan_id }
      ]
    );

    await auditLogService.log({
      target_type: 'subscription',
      target_id: subscription.id,
      action: 'paypal.saas_subscription_create',
      after_data: {
        user_id: userId,
        plan_id: plan.id,
        paypal_plan_id: plan.paypal_plan_id,
        paypal_subscription_id: paypalSubscription.id,
        estado: subscription.estado
      }
    }, { client, req });

    await client.query('COMMIT');
    return {
      subscription,
      paypal_subscription_id: paypalSubscription.id,
      approval_url: approvalUrlFromLinks(paypalSubscription.links || []),
      estado: 'pendiente',
      status: paypalSubscription.status || 'APPROVAL_PENDING'
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function findSaasSubscription({ paypalSubscriptionId, customId, client, forUpdate = false }) {
  const lockSql = forUpdate ? ' FOR UPDATE' : '';
  if (paypalSubscriptionId) {
    const res = await client.query(
      `SELECT ss.*, sp.nombre AS plan_nombre, sp.tipo AS plan_tipo, sp.precio AS plan_precio, sp.moneda AS plan_moneda
       FROM saas_suscripciones ss
       INNER JOIN saas_planes sp ON sp.id = ss.plan_id
       WHERE ss.paypal_subscription_id = $1${lockSql}`,
      [paypalSubscriptionId]
    );
    if (res.rows[0]) return res.rows[0];
  }
  if (customId) {
    const res = await client.query(
      `SELECT ss.*, sp.nombre AS plan_nombre, sp.tipo AS plan_tipo, sp.precio AS plan_precio, sp.moneda AS plan_moneda
       FROM saas_suscripciones ss
       INNER JOIN saas_planes sp ON sp.id = ss.plan_id
       WHERE ss.id = $1${lockSql}`,
      [customId]
    );
    return res.rows[0] || null;
  }
  return null;
}

async function ensureUserSaasSubscriptionLicense(subscription, { client, paypalSubscriptionId, nextPaymentDate }) {
  const existing = await client.query(
    `SELECT * FROM saas_licencias
     WHERE suscripcion_id = $1 AND tipo = 'suscripcion'
     ORDER BY created_at DESC
     LIMIT 1`,
    [subscription.id]
  );
  if (existing.rows[0]) {
    const updated = await client.query(
      `UPDATE saas_licencias
       SET estado = 'activa',
           fecha_activacion = COALESCE(fecha_activacion, now()),
           fecha_expiracion = COALESCE($2, fecha_expiracion),
           metadata = metadata || $3::jsonb,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [
        existing.rows[0].id,
        nextPaymentDate || null,
        JSON.stringify({ paypal_subscription_id: paypalSubscriptionId, last_renewal_source: 'paypal_webhook' })
      ]
    );
    return updated.rows[0];
  }

  for (let attempt = 0; attempt < 8; attempt++) {
    const licenseKey = generateLicenseKey('FULL');
    try {
      const res = await client.query(
        `INSERT INTO saas_licencias (
           user_id, plan_id, suscripcion_id, tipo, estado,
           fecha_activacion, fecha_expiracion, license_key, metadata
         ) VALUES ($1,$2,$3,'suscripcion','activa',now(),$4,$5,$6)
         RETURNING *`,
        [
          subscription.user_id,
          subscription.plan_id,
          subscription.id,
          nextPaymentDate || null,
          licenseKey,
          { source: 'paypal_subscription', paypal_subscription_id: paypalSubscriptionId }
        ]
      );
      return res.rows[0];
    } catch (error) {
      if (error?.code === '23505') continue;
      throw error;
    }
  }

  throw httpError(500, 'LICENSE_KEY_GENERATION_FAILED', 'No se pudo generar la licencia de suscripción');
}

async function createSubscription(payload, { req } = {}) {
  if (!payload?.company_id || payload?.user_id || payload?.usuario_id) {
    return createUserSaasSubscription(payload, { req });
  }

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

async function cancelSubscription(payload, { req } = {}) {
  const paypalSubscriptionId = String(
    payload?.paypal_subscription_id || payload?.subscription_id || ''
  ).trim();
  if (!paypalSubscriptionId) {
    throw httpError(400, 'PAYPAL_SUBSCRIPTION_REQUIRED', 'paypal_subscription_id es requerido');
  }

  const reason = String(payload?.reason || 'Cancelada desde el sistema SaaS').trim();
  await paypalRequest(
    'POST',
    `/v1/billing/subscriptions/${encodeURIComponent(paypalSubscriptionId)}/cancel`,
    { reason }
  );

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const subscription = await subscriptionsModel.findByPayPalSubscriptionId(paypalSubscriptionId, {
      client,
      forUpdate: true
    });

    if (!subscription) {
      await client.query('COMMIT');
      return { ok: true, paypal_subscription_id: paypalSubscriptionId, local_subscription: null };
    }

    const updated = await subscriptionsModel.updateById(subscription.id, {
      status: 'CANCELLED',
      cancelled_at: new Date(),
      metadata: { ...(subscription.metadata || {}), paypal_cancel_reason: reason }
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
      action: 'paypal.subscription_cancel_request',
      after_data: { paypal_subscription_id: paypalSubscriptionId, status: updated.status, reason }
    }, { client, req });

    await client.query('COMMIT');
    return { ok: true, paypal_subscription_id: paypalSubscriptionId, subscription: updated };
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

function paypalSubscriptionIdFromSale(resource) {
  return resource?.billing_agreement_id || resource?.billing_agreement?.id || resource?.subscription_id || null;
}

function nextSaasExpiration(subscription, paidAt) {
  const now = paidAt || new Date();
  const current = subscription.fecha_expiracion || subscription.proximo_pago || subscription.fecha_fin;
  const currentDate = current ? new Date(current) : null;
  const base = currentDate && currentDate.getTime() > now.getTime() ? currentDate : now;
  const next = new Date(base);
  if (subscription.plan_tipo === 'anual') {
    next.setFullYear(next.getFullYear() + 1);
  } else {
    next.setMonth(next.getMonth() + 1);
  }
  return next;
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
  if (!subscription) {
    const saasSubscription = await findSaasSubscription({
      paypalSubscriptionId,
      customId: resource.custom_id,
      client,
      forUpdate: true
    });
    if (!saasSubscription) throw httpError(404, 'LOCAL_SUBSCRIPTION_NOT_FOUND', 'Suscripción local no encontrada');

    const nextPaymentDate = nextBillingDateFromResource(resource) || saasSubscription.proximo_pago;
    const updatedRes = await client.query(
      `UPDATE saas_suscripciones
       SET estado = 'activa',
           paypal_subscription_id = $2,
           proximo_pago = $3,
           metadata = metadata || $4::jsonb,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [
        saasSubscription.id,
        paypalSubscriptionId,
        nextPaymentDate,
        JSON.stringify({ paypal_last_event: event.event_type })
      ]
    );

    await auditLogService.log({
      target_type: 'subscription',
      target_id: updatedRes.rows[0].id,
      action: 'paypal.saas_subscription_activated',
      after_data: { paypal_subscription_id: paypalSubscriptionId, proximo_pago: nextPaymentDate }
    }, { client, req });

    return updatedRes.rows[0];
  }

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
  const paypalSubscriptionId = paypalSubscriptionIdFromSale(resource);
  if (!paypalSubscriptionId) throw httpError(400, 'PAYPAL_SUBSCRIPTION_ID_MISSING', 'Evento sin billing_agreement_id');

  let subscription = await subscriptionsModel.findByPayPalSubscriptionId(paypalSubscriptionId, { client, forUpdate: true });
  if (!subscription) {
    const saasSubscription = await findSaasSubscription({ paypalSubscriptionId, client, forUpdate: true });
    if (!saasSubscription) throw httpError(404, 'LOCAL_SUBSCRIPTION_NOT_FOUND', 'Suscripción local no encontrada');

    const existingPayment = await client.query(
      `SELECT * FROM saas_pagos
       WHERE paypal_payment_id = $1
       LIMIT 1`,
      [resource.id]
    );
    if (existingPayment.rows[0]) return { payment: existingPayment.rows[0], subscription: saasSubscription, idempotent: true };

    const paidAt = resource.create_time ? new Date(resource.create_time) : new Date();
    const nextPaymentDate = nextBillingDateFromResource(resource) || nextSaasExpiration(saasSubscription, paidAt);
    const license = await ensureUserSaasSubscriptionLicense(saasSubscription, {
      client,
      paypalSubscriptionId,
      nextPaymentDate
    });
    const amount = Number(resource.amount?.total || resource.amount?.value || saasSubscription.plan_precio || 0);
    const currency = resource.amount?.currency || resource.amount?.currency_code || saasSubscription.plan_moneda || 'USD';

    const paymentRes = await client.query(
      `INSERT INTO saas_pagos (
         user_id, suscripcion_id, licencia_id, tipo, paypal_payment_id,
         paypal_subscription_id, monto, moneda, estado, fecha_pago, paypal_payload, metadata
       ) VALUES ($1,$2,$3,'paypal',$4,$5,$6,$7,'completado',$8,$9,$10)
       RETURNING *`,
      [
        saasSubscription.user_id,
        saasSubscription.id,
        license.id,
        resource.id || null,
        paypalSubscriptionId,
        amount,
        currency,
        paidAt,
        event,
        { source: 'paypal_subscription_payment' }
      ]
    );

    const updatedSubscriptionRes = await client.query(
      `UPDATE saas_suscripciones
       SET estado = 'activa',
           proximo_pago = COALESCE($2, proximo_pago),
           metadata = metadata || $3::jsonb,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [
        saasSubscription.id,
        nextPaymentDate,
        JSON.stringify({ paypal_last_event: event.event_type, last_payment_id: resource.id || null })
      ]
    );

    await client.query(
      `UPDATE platform_users SET status = 'active', updated_at = now() WHERE id = $1`,
      [saasSubscription.user_id]
    );

    return {
      payment: paymentRes.rows[0],
      subscription: updatedSubscriptionRes.rows[0],
      license,
      idempotent: false
    };
  }

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
  if (!subscription) {
    const saasSubscription = await findSaasSubscription({
      paypalSubscriptionId,
      customId: resource.custom_id,
      client,
      forUpdate: true
    });
    if (!saasSubscription) throw httpError(404, 'LOCAL_SUBSCRIPTION_NOT_FOUND', 'Suscripción local no encontrada');

    const updatedRes = await client.query(
      `UPDATE saas_suscripciones
       SET estado = 'cancelada',
           fecha_fin = COALESCE(fecha_fin, now()),
           metadata = metadata || $2::jsonb,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [
        saasSubscription.id,
        JSON.stringify({ paypal_last_event: event.event_type, paypal_cancelled_at: new Date().toISOString() })
      ]
    );

    await client.query(
      `UPDATE saas_licencias
       SET estado = 'bloqueada', updated_at = now()
       WHERE suscripcion_id = $1`,
      [saasSubscription.id]
    );

    await auditLogService.log({
      target_type: 'subscription',
      target_id: updatedRes.rows[0].id,
      action: 'paypal.saas_subscription_cancelled',
      after_data: { paypal_subscription_id: paypalSubscriptionId, estado: updatedRes.rows[0].estado }
    }, { client, req });

    return updatedRes.rows[0];
  }

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

async function handleSaleDenied(event, { client, req }) {
  const resource = event.resource || {};
  const paypalSubscriptionId = paypalSubscriptionIdFromSale(resource);
  if (!paypalSubscriptionId) throw httpError(400, 'PAYPAL_SUBSCRIPTION_ID_MISSING', 'Evento sin billing_agreement_id');

  const amount = Number(resource.amount?.total || resource.amount?.value || 0);
  const currency = resource.amount?.currency || resource.amount?.currency_code || 'USD';
  const reason = resource.reason_code || resource.state || resource.status || 'PAYMENT.SALE.DENIED';

  let subscription = await subscriptionsModel.findByPayPalSubscriptionId(paypalSubscriptionId, { client, forUpdate: true });
  if (!subscription) {
    const saasSubscription = await findSaasSubscription({ paypalSubscriptionId, client, forUpdate: true });
    if (!saasSubscription) throw httpError(404, 'LOCAL_SUBSCRIPTION_NOT_FOUND', 'Suscripción local no encontrada');

    const existingPayment = await client.query(
      `SELECT * FROM saas_pagos
       WHERE paypal_payment_id = $1
       LIMIT 1`,
      [resource.id]
    );
    if (existingPayment.rows[0]) return { payment: existingPayment.rows[0], subscription: saasSubscription, idempotent: true };

    const paymentRes = await client.query(
      `INSERT INTO saas_pagos (
         user_id, suscripcion_id, tipo, paypal_payment_id,
         paypal_subscription_id, monto, moneda, estado, paypal_payload, metadata
       ) VALUES ($1,$2,'paypal',$3,$4,$5,$6,'fallido',$7,$8)
       RETURNING *`,
      [
        saasSubscription.user_id,
        saasSubscription.id,
        resource.id || null,
        paypalSubscriptionId,
        amount || Number(saasSubscription.plan_precio || 0),
        currency || saasSubscription.plan_moneda || 'USD',
        event,
        { reason }
      ]
    );

    const updatedSubscriptionRes = await client.query(
      `UPDATE saas_suscripciones
       SET estado = 'vencida',
         metadata = metadata || $2::jsonb,
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [
        saasSubscription.id,
        JSON.stringify({ paypal_last_event: event.event_type, last_failed_payment_id: resource.id || null, last_failure_reason: reason })
      ]
    );

    await client.query(
      `UPDATE saas_licencias
       SET estado = 'bloqueada', updated_at = now()
       WHERE suscripcion_id = $1`,
      [saasSubscription.id]
    );

    await client.query(
      `UPDATE platform_users
       SET status = 'suspended', updated_at = now()
       WHERE id = $1`,
      [saasSubscription.user_id]
    );

    return { payment: paymentRes.rows[0], subscription: updatedSubscriptionRes.rows[0], idempotent: false };
  }

  const existingPayment = await paymentsModel.findByReference(subscription.id, resource.id, { client, forUpdate: true });
  if (existingPayment) return { payment: existingPayment, subscription, idempotent: true };

  const payment = await paymentsModel.create({
    company_id: subscription.company_id,
    subscription_id: subscription.id,
    product_id: subscription.product_id,
    project_id: subscription.project_id,
    license_id: subscription.license_id,
    amount: amount || Number(subscription.amount || 0),
    currency,
    status: 'failed',
    payment_method: 'paypal',
    reference: resource.id,
    notes: `Pago PayPal denegado: ${reason}`,
    gateway_payload: event,
    paypal_subscription_id: paypalSubscriptionId,
    paypal_capture_id: resource.id || null
  }, { client });

  const updated = await subscriptionsModel.updateById(subscription.id, {
    status: subscription.status === 'ACTIVE' ? 'GRACE' : 'PENDING_PAYMENT',
    metadata: { ...(subscription.metadata || {}), paypal_last_event: event.event_type, last_failure_reason: reason }
  }, { client });

  await auditLogService.log({
    company_id: subscription.company_id,
    product_id: subscription.product_id,
    project_id: subscription.project_id,
    target_type: 'payment',
    target_id: payment.id,
    action: 'paypal.sale_denied',
    after_data: { paypal_subscription_id: paypalSubscriptionId, reference: resource.id || null, reason }
  }, { client, req });

  return { payment, subscription: updated, idempotent: false };
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
    } else if (event.event_type === 'PAYMENT.SALE.DENIED') {
      result = await handleSaleDenied(event, { client, req });
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
  getPaymentStatus,
  cancelSubscription,
  syncPlanToPayPal,
  syncRecurringPlansToPayPal,
  processWebhook,
  paypalRequest,
  getAccessToken,
  paypalBaseUrl,
  httpError
};
