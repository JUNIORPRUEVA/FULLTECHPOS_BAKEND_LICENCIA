const { pool } = require('../db/pool');

const productPlansModel = require('../models/productPlansModel');
const subscriptionsModel = require('../models/subscriptionsModel');
const auditLogService = require('./auditLogService');

const VALID_STATUSES = new Set(['ACTIVE', 'PENDING_PAYMENT', 'GRACE', 'EXPIRED', 'CANCELLED']);

const STATUS_ALIASES = {
  trial: 'ACTIVE',
  active: 'ACTIVE',
  lifetime: 'ACTIVE',
  past_due: 'PENDING_PAYMENT',
  suspended: 'EXPIRED',
  expired: 'EXPIRED',
  cancelled: 'CANCELLED'
};

function normalizeUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

function asDate(value, fallback = null) {
  if (!value) return fallback;
  const next = new Date(value);
  if (Number.isNaN(next.getTime())) throw new Error('fecha inválida');
  return next;
}

function normalizeSubscriptionStatus(value, fallback = null) {
  if (!value) return fallback;
  const raw = String(value).trim();
  if (!raw) return fallback;
  const upper = raw.toUpperCase();
  if (VALID_STATUSES.has(upper)) return upper;
  return STATUS_ALIASES[raw.toLowerCase()] || null;
}

function normalizeOptionalAmount(value, fallback = null) {
  if (value == null || value === '') return fallback;
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount < 0) throw new Error('amount inválido');
  return amount;
}

function resolveLicenseType(plan, payload = {}) {
  const requested = payload.license_type ? String(payload.license_type).trim().toUpperCase() : null;
  if (requested) {
    if (!['PERMANENTE', 'SUSCRIPCION'].includes(requested)) throw new Error('license_type inválido');
    return requested;
  }
  return plan.billing_period === 'lifetime' ? 'PERMANENTE' : 'SUSCRIPCION';
}

function addBillingPeriod(baseDate, plan) {
  const start = new Date(baseDate);
  const end = new Date(start);

  if (plan.billing_period === 'trial') {
    end.setUTCDate(end.getUTCDate() + Math.max(0, Number(plan.trial_days) || 0));
  } else if (plan.billing_period === 'monthly') {
    end.setUTCMonth(end.getUTCMonth() + 1);
  } else if (plan.billing_period === 'annual') {
    end.setUTCFullYear(end.getUTCFullYear() + 1);
  } else if (plan.billing_period === 'lifetime') {
    return { endDate: null, renewalDate: null, nextPaymentDate: null, status: 'ACTIVE', billedDays: null };
  }

  const billedDays = Math.max(0, Math.ceil((end.getTime() - start.getTime()) / (24 * 60 * 60 * 1000)));
  return {
    endDate: end,
    renewalDate: end,
    nextPaymentDate: end,
    status: 'ACTIVE',
    billedDays
  };
}

async function ensureCompanyExists(companyId, client) {
  const res = await client.query('SELECT id, name FROM companies WHERE id = $1', [companyId]);
  return res.rows[0] || null;
}

function resolveOwnership(payload, plan) {
  const productId = payload.product_id === undefined ? plan.product_id : normalizeUuid(payload.product_id);
  const projectId = payload.project_id === undefined ? plan.project_id : normalizeUuid(payload.project_id);

  if ((productId ? 1 : 0) === (projectId ? 1 : 0)) {
    throw new Error('La suscripción debe apuntar a exactamente uno entre product_id o project_id');
  }
  if (plan.product_id && productId !== plan.product_id) {
    throw new Error('product_id no coincide con el plan');
  }
  if (plan.project_id && projectId !== plan.project_id) {
    throw new Error('project_id no coincide con el plan');
  }

  return { product_id: productId, project_id: projectId };
}

async function createSubscription(payload, { req } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const companyId = normalizeUuid(payload.company_id);
    const planId = normalizeUuid(payload.plan_id);
    if (!companyId) throw new Error('company_id inválido');
    if (!planId) throw new Error('plan_id inválido');

    const company = await ensureCompanyExists(companyId, client);
    if (!company) throw new Error('company no existe');

    const plan = await productPlansModel.getById(planId, { client });
    if (!plan) throw new Error('plan no existe');

    const ownership = resolveOwnership(payload, plan);
    const startDate = asDate(payload.start_date, new Date());
    const derived = addBillingPeriod(startDate, plan);
    const licenseType = resolveLicenseType(plan, payload);
    const status = normalizeSubscriptionStatus(payload.status, derived.status);
    if (!VALID_STATUSES.has(status)) throw new Error('status inválido');

    const endDate = licenseType === 'PERMANENTE'
      ? null
      : (payload.end_date ? asDate(payload.end_date) : derived.endDate);
    const renewalDate = licenseType === 'PERMANENTE'
      ? null
      : (payload.renewal_date ? asDate(payload.renewal_date) : derived.renewalDate);
    const nextPaymentDate = licenseType === 'PERMANENTE'
      ? null
      : (payload.next_payment_date ? asDate(payload.next_payment_date) : derived.nextPaymentDate || renewalDate || endDate);

    const created = await subscriptionsModel.create({
      company_id: company.id,
      customer_id: normalizeUuid(payload.customer_id),
      license_id: normalizeUuid(payload.license_id),
      product_id: ownership.product_id,
      project_id: ownership.project_id,
      plan_id: plan.id,
      amount: normalizeOptionalAmount(payload.amount, Number(plan.price_amount || 0)),
      next_payment_date: nextPaymentDate,
      license_type: licenseType,
      status,
      start_date: startDate,
      end_date: endDate,
      renewal_date: renewalDate,
      grace_until: payload.grace_until ? asDate(payload.grace_until) : null,
      notes: payload.notes ? String(payload.notes) : null,
      metadata: payload.metadata && typeof payload.metadata === 'object' ? payload.metadata : {},
      created_by: normalizeUuid(payload.created_by),
      updated_by: normalizeUuid(payload.updated_by) || normalizeUuid(payload.created_by)
    }, { client });

    await auditLogService.log({
      company_id: company.id,
      product_id: ownership.product_id,
      project_id: ownership.project_id,
      target_type: 'subscription',
      target_id: created.id,
      action: 'subscription.create',
      after_data: created
    }, { client, req });

    await client.query('COMMIT');
    return created;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function updateStatus(subscriptionId, status, payload = {}, { req } = {}) {
  const normalized = normalizeSubscriptionStatus(status);
  if (!VALID_STATUSES.has(normalized)) throw new Error('status inválido');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await subscriptionsModel.getById(subscriptionId, { client, forUpdate: true });
    if (!current) throw new Error('Suscripción no encontrada');

    const patch = {
      status: normalized,
      updated_by: normalizeUuid(payload.updated_by) || null
    };
    if (normalized === 'CANCELLED') patch.cancelled_at = new Date();
    if (normalized === 'EXPIRED') patch.suspended_at = payload.suspended_at ? asDate(payload.suspended_at) : current.suspended_at;
    if (payload.notes !== undefined) patch.notes = payload.notes == null ? null : String(payload.notes);

    const updated = await subscriptionsModel.updateById(subscriptionId, patch, { client });

    await auditLogService.log({
      company_id: updated.company_id,
      product_id: updated.product_id,
      project_id: updated.project_id,
      target_type: 'subscription',
      target_id: updated.id,
      action: 'subscription.status_update',
      before_data: current,
      after_data: updated
    }, { client, req });

    await client.query('COMMIT');
    return updated;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function extendDates(subscriptionId, payload = {}, { req } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await subscriptionsModel.getById(subscriptionId, { client, forUpdate: true });
    if (!current) throw new Error('Suscripción no encontrada');

    const days = payload.days == null ? null : Math.floor(Number(payload.days));
    if (days != null && (!Number.isFinite(days) || days <= 0)) {
      throw new Error('days inválido');
    }

    let endDate = current.end_date ? new Date(current.end_date) : null;
    if (payload.end_date) {
      endDate = asDate(payload.end_date);
    } else if (days != null) {
      const base = endDate && endDate.getTime() > Date.now() ? endDate : new Date();
      endDate = new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
    }

    const renewalDate = payload.renewal_date ? asDate(payload.renewal_date) : endDate;
    const nextPaymentDate = payload.next_payment_date ? asDate(payload.next_payment_date) : renewalDate;
    const updated = await subscriptionsModel.updateById(subscriptionId, {
      end_date: endDate,
      renewal_date: renewalDate,
      next_payment_date: nextPaymentDate,
      grace_until: payload.grace_until ? asDate(payload.grace_until) : current.grace_until,
      updated_by: normalizeUuid(payload.updated_by) || null,
      notes: payload.notes === undefined ? current.notes : payload.notes
    }, { client });

    await auditLogService.log({
      company_id: updated.company_id,
      product_id: updated.product_id,
      project_id: updated.project_id,
      target_type: 'subscription',
      target_id: updated.id,
      action: 'subscription.extend',
      before_data: current,
      after_data: updated
    }, { client, req });

    await client.query('COMMIT');
    return updated;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  addBillingPeriod,
  normalizeSubscriptionStatus,
  createSubscription,
  updateStatus,
  extendDates
};