const { pool } = require('../db/pool');

const paymentsModel = require('../models/paymentsModel');
const productPlansModel = require('../models/productPlansModel');
const subscriptionsModel = require('../models/subscriptionsModel');
const licensesModel = require('../models/licensesModel');
const auditLogService = require('./auditLogService');
const { addBillingPeriod } = require('./subscriptionService');

const VALID_STATUSES = new Set(['pending', 'paid', 'failed', 'refunded', 'cancelled']);
const VALID_METHODS = new Set(['manual', 'cash', 'transfer', 'card', 'paypal', 'other']);

function normalizeUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

function normalizeText(value, { lower = false, upper = false } = {}) {
  if (value == null) return null;
  let next = String(value).trim();
  if (!next) return null;
  if (lower) next = next.toLowerCase();
  if (upper) next = next.toUpperCase();
  return next;
}

function asDate(value) {
  if (!value) return null;
  const next = new Date(value);
  if (Number.isNaN(next.getTime())) throw new Error('fecha inválida');
  return next;
}

async function ensureLicenseExists(licenseId, client) {
  if (!licenseId) return null;
  const license = await licensesModel.getLicenseById(licenseId);
  if (!license) throw new Error('license_id no existe');
  return license;
}

async function applyPaidPaymentEffects({ subscription, payment, plan, client, req }) {
  const now = new Date();
  const previousDue = subscription.next_payment_date || subscription.renewal_date || subscription.end_date;
  const previousDueDate = previousDue ? new Date(previousDue) : null;
  const base = previousDueDate && previousDueDate.getTime() > now.getTime() ? previousDueDate : now;
  const derived = addBillingPeriod(base, plan);
  const licenseType = plan.billing_period === 'lifetime' ? 'PERMANENTE' : 'SUSCRIPCION';

  const updatedSubscription = await subscriptionsModel.updateById(subscription.id, {
    status: 'ACTIVE',
    amount: payment.amount,
    next_payment_date: derived.nextPaymentDate,
    license_type: licenseType,
    end_date: derived.endDate,
    renewal_date: derived.renewalDate,
    grace_until: null,
    suspended_at: null,
    cancelled_at: subscription.cancelled_at,
    updated_by: payment.recorded_by || null
  }, { client });

  let linkedLicense = null;
  const licenseId = payment.license_id || subscription.license_id;
  if (licenseId) {
    const licenseRes = await client.query(
      `UPDATE licenses
       SET company_id = COALESCE(company_id, $2),
           subscription_id = $3,
           product_id = COALESCE($4, product_id),
           license_type = $5,
           estado = 'ACTIVA',
           issued_at = COALESCE(issued_at, now()),
           fecha_inicio = COALESCE(fecha_inicio, now()),
           fecha_fin = $6,
           expires_at = $6
       WHERE id = $1
       RETURNING *`,
      [licenseId, subscription.company_id, subscription.id, subscription.product_id || null, licenseType, derived.endDate]
    );
    linkedLicense = licenseRes.rows[0] || null;

    await client.query(
      `UPDATE company_subscriptions
       SET license_id = COALESCE(license_id, $2),
           customer_id = COALESCE(customer_id, $3),
           updated_at = now()
       WHERE id = $1`,
      [subscription.id, licenseId, linkedLicense?.customer_id || null]
    );
  }

  await auditLogService.log({
    company_id: subscription.company_id,
    product_id: subscription.product_id,
    project_id: subscription.project_id,
    target_type: 'payment',
    target_id: payment.id,
    action: 'payment.paid',
    before_data: { subscription_before: subscription },
    after_data: { payment, subscription_after: updatedSubscription, license_after: linkedLicense }
  }, { client, req });

  return { updatedSubscription, linkedLicense };
}

async function registerManualPayment(payload, { req } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const subscriptionId = normalizeUuid(payload.subscription_id);
    if (!subscriptionId) throw new Error('subscription_id inválido');

    const amount = Number(payload.amount);
    if (!Number.isFinite(amount) || amount < 0) throw new Error('amount inválido');

    const subscription = await subscriptionsModel.getById(subscriptionId, { client, forUpdate: true });
    if (!subscription) throw new Error('Suscripción no encontrada');

    const companyId = normalizeUuid(payload.company_id) || subscription.company_id;
    if (companyId !== subscription.company_id) throw new Error('company_id no coincide con la suscripción');

    const reference = normalizeText(payload.reference);
    if (reference) {
      const existing = await paymentsModel.findByReference(subscription.id, reference, { client, forUpdate: true });
      if (existing) {
        await client.query('COMMIT');
        return { payment: existing, subscription, idempotent: true };
      }
    }

    const plan = await productPlansModel.getById(subscription.plan_id, { client });
    if (!plan) throw new Error('Plan asociado no encontrado');

    const status = normalizeText(payload.status, { lower: true }) || 'pending';
    if (!VALID_STATUSES.has(status)) throw new Error('status inválido');

    const paymentMethod = normalizeText(payload.payment_method, { lower: true }) || 'manual';
    if (!VALID_METHODS.has(paymentMethod)) throw new Error('payment_method inválido');

    await ensureLicenseExists(normalizeUuid(payload.license_id), client);

    const payment = await paymentsModel.create({
      company_id: companyId,
      subscription_id: subscription.id,
      product_id: subscription.product_id,
      project_id: subscription.project_id,
      license_id: normalizeUuid(payload.license_id),
      amount,
      currency: normalizeText(payload.currency, { upper: true }) || 'DOP',
      status,
      payment_method: paymentMethod,
      reference,
      notes: payload.notes ? String(payload.notes) : null,
      paid_at: status === 'paid' ? asDate(payload.paid_at) || new Date() : null,
      payment_date: payload.date ? asDate(payload.date) : (payload.payment_date ? asDate(payload.payment_date) : null),
      recorded_by: normalizeUuid(payload.recorded_by),
      gateway_payload: payload.gateway_payload && typeof payload.gateway_payload === 'object' ? payload.gateway_payload : {}
    }, { client });

    await auditLogService.log({
      company_id: payment.company_id,
      product_id: payment.product_id,
      project_id: payment.project_id,
      target_type: 'payment',
      target_id: payment.id,
      action: 'payment.register_manual',
      after_data: payment
    }, { client, req });

    let sideEffects = null;
    if (status === 'paid') {
      sideEffects = await applyPaidPaymentEffects({ subscription, payment, plan, client, req });
    }

    await client.query('COMMIT');
    return {
      payment,
      subscription: sideEffects?.updatedSubscription || subscription,
      license: sideEffects?.linkedLicense || null,
      idempotent: false
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  registerManualPayment,
  applyPaidPaymentEffects
};