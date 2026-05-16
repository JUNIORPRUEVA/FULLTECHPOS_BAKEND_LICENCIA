const licenseValidationModel = require('../models/licenseValidationModel');
const auditLogService = require('./auditLogService');

const ALLOWED_OUTPUT_STATUS = new Set([
  'active',
  'trial',
  'grace',
  'expired',
  'suspended',
  'cancelled',
  'blocked',
  'not_found',
  'invalid'
]);

function normalizeUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

function normalizeText(value) {
  const raw = String(value || '').trim();
  return raw || null;
}

function isDateExpired(value, now = new Date()) {
  if (!value) return false;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return false;
  return dt.getTime() < now.getTime();
}

function isFutureDate(value, now = new Date()) {
  if (!value) return false;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return false;
  return dt.getTime() >= now.getTime();
}

function maskLicenseKey(value) {
  const raw = String(value || '').trim();
  if (!raw) return null;
  if (raw.length <= 8) return `${raw.slice(0, 2)}***${raw.slice(-2)}`;
  return `${raw.slice(0, 4)}***${raw.slice(-4)}`;
}

function baseResponse() {
  return {
    success: true,
    status: 'invalid',
    can_access: false,
    reason: 'invalid_request',
    company: null,
    product: null,
    project: null,
    plan: null,
    subscription: null,
    license: null,
    limits: null,
    server_time: new Date().toISOString(),
    offline_grace_until: null
  };
}

function mapLicenseCore(license) {
  if (!license) return null;
  return {
    id: license.id,
    key: maskLicenseKey(license.license_key),
    tipo: license.tipo,
    estado: license.estado,
    fecha_inicio: license.fecha_inicio || null,
    fecha_fin: license.fecha_fin || null,
    issued_at: license.issued_at || null,
    subscription_id: license.subscription_id || null
  };
}

function mapSubscriptionCore(subscription) {
  if (!subscription) return null;
  return {
    id: subscription.id,
    status: subscription.status,
    start_date: subscription.start_date,
    end_date: subscription.end_date,
    renewal_date: subscription.renewal_date,
    grace_until: subscription.grace_until,
    cancelled_at: subscription.cancelled_at,
    suspended_at: subscription.suspended_at
  };
}

function mapPlanCore(subscription) {
  if (!subscription) return null;
  return {
    id: subscription.plan_id,
    code: subscription.plan_code,
    name: subscription.plan_name,
    billing_period: subscription.billing_period
  };
}

function evaluateSubscriptionStatus(subscription, now = new Date()) {
  if (!subscription) return { status: null, can_access: null, reason: null };

  const subStatus = String(subscription.status || '').toLowerCase();

  if (subStatus === 'active' || subStatus === 'lifetime') {
    return { status: 'active', can_access: true, reason: 'subscription_active' };
  }
  if (subStatus === 'trial') {
    return { status: 'trial', can_access: true, reason: 'subscription_trial' };
  }

  if (['past_due', 'expired', 'suspended', 'cancelled'].includes(subStatus)) {
    if (isFutureDate(subscription.grace_until, now)) {
      return { status: 'grace', can_access: true, reason: 'subscription_grace_period' };
    }

    if (subStatus === 'past_due' || subStatus === 'expired') {
      return { status: 'expired', can_access: false, reason: `subscription_${subStatus}` };
    }
    if (subStatus === 'suspended') {
      return { status: 'suspended', can_access: false, reason: 'subscription_suspended' };
    }
    return { status: 'cancelled', can_access: false, reason: 'subscription_cancelled' };
  }

  return { status: 'invalid', can_access: false, reason: 'subscription_invalid_status' };
}

function evaluateLicenseStatus(license, now = new Date()) {
  if (!license) return { status: null, can_access: null, reason: null };

  const state = String(license.estado || '').toUpperCase();
  if (state === 'BLOQUEADA' || state === 'ELIMINADA') {
    return { status: 'blocked', can_access: false, reason: 'license_blocked' };
  }
  if (state === 'VENCIDA' || isDateExpired(license.fecha_fin, now)) {
    return { status: 'expired', can_access: false, reason: 'license_expired' };
  }

  if (state === 'ACTIVA' || state === 'PENDIENTE') {
    const normalized = String(license.tipo || '').toUpperCase() === 'DEMO' ? 'trial' : 'active';
    return { status: normalized, can_access: true, reason: 'license_valid' };
  }

  return { status: 'invalid', can_access: false, reason: 'license_invalid_status' };
}

function resolveFinalStatus({ subscriptionDecision, licenseDecision }) {
  if (subscriptionDecision?.status && !subscriptionDecision.can_access) {
    return subscriptionDecision;
  }
  if (licenseDecision?.status && !licenseDecision.can_access) {
    return licenseDecision;
  }

  if (subscriptionDecision?.status === 'grace') {
    return subscriptionDecision;
  }
  if (subscriptionDecision?.status === 'trial') {
    return subscriptionDecision;
  }
  if (licenseDecision?.status === 'trial') {
    return licenseDecision;
  }

  if (subscriptionDecision?.status === 'active' && licenseDecision?.status === 'active') {
    return { status: 'active', can_access: true, reason: 'subscription_and_license_active' };
  }
  if (subscriptionDecision?.status === 'active') {
    return { status: 'active', can_access: true, reason: subscriptionDecision.reason || 'subscription_active' };
  }
  if (licenseDecision?.status === 'active') {
    return { status: 'active', can_access: true, reason: licenseDecision.reason || 'license_active' };
  }

  return { status: 'not_found', can_access: false, reason: 'license_or_subscription_not_found' };
}

function sanitizeInput(payload) {
  const body = payload || {};
  return {
    license_key: normalizeText(body.license_key),
    company_id: normalizeUuid(body.company_id),
    business_id: normalizeText(body.business_id),
    product_id: normalizeUuid(body.product_id),
    project_id: normalizeUuid(body.project_id),
    device_id: normalizeText(body.device_id)
  };
}

async function validateLicense(payload, { req } = {}) {
  const response = baseResponse();
  const now = new Date();
  response.server_time = now.toISOString();

  const input = sanitizeInput(payload);
  const hasAnyIdentifier = Boolean(
    input.license_key || input.company_id || input.business_id || input.product_id || input.project_id || input.device_id
  );

  if (!hasAnyIdentifier) {
    response.status = 'invalid';
    response.reason = 'at_least_one_identifier_required';
    return response;
  }

  let license = null;
  let subscription = null;

  if (input.license_key) {
    license = await licenseValidationModel.findLicenseByKey(input.license_key);
  }

  if (!license && input.business_id) {
    license = await licenseValidationModel.findLatestLicenseByBusinessId(input.business_id, {
      product_id: input.product_id,
      project_id: input.project_id,
      device_id: input.device_id
    });
  }

  if (license && input.product_id && license.product_id && license.product_id !== input.product_id) {
    response.status = 'invalid';
    response.reason = 'license_product_mismatch';
    response.license = mapLicenseCore(license);
    response.offline_grace_until = license.offline_grace_until || null;
    await maybeWriteValidationAudit({ req, input, response, license, subscription: null });
    return response;
  }
  if (license && input.project_id && license.project_id && license.project_id !== input.project_id) {
    response.status = 'invalid';
    response.reason = 'license_project_mismatch';
    response.license = mapLicenseCore(license);
    response.offline_grace_until = license.offline_grace_until || null;
    await maybeWriteValidationAudit({ req, input, response, license, subscription: null });
    return response;
  }

  const subscriptionId = license?.subscription_id || null;
  if (subscriptionId) {
    subscription = await licenseValidationModel.findSubscriptionById(subscriptionId);
  }

  if (!subscription) {
    subscription = await licenseValidationModel.findLatestSubscriptionByFilters({
      company_id: input.company_id || license?.company_id || null,
      product_id: input.product_id || license?.product_id || null,
      project_id: input.project_id || license?.project_id || null
    });
  }

  if (input.company_id && subscription && subscription.company_id !== input.company_id) {
    response.status = 'invalid';
    response.reason = 'company_mismatch';
    response.subscription = mapSubscriptionCore(subscription);
    response.plan = mapPlanCore(subscription);
    response.company = subscription.company_id
      ? { id: subscription.company_id, name: subscription.company_name || null }
      : null;
    response.license = mapLicenseCore(license);
    response.offline_grace_until = license?.offline_grace_until || null;
    await maybeWriteValidationAudit({ req, input, response, license, subscription });
    return response;
  }

  let usedDevices = null;
  let deviceActivation = null;
  if (license?.id) {
    usedDevices = await licenseValidationModel.countActiveActivations(license.id);
    if (input.device_id) {
      deviceActivation = await licenseValidationModel.findDeviceActivation(license.id, input.device_id);
    }
  }

  const licenseDecision = evaluateLicenseStatus(license, now);
  const subscriptionDecision = evaluateSubscriptionStatus(subscription, now);

  let finalDecision = resolveFinalStatus({ subscriptionDecision, licenseDecision });

  const activationStatus = deviceActivation?.status || (deviceActivation?.estado === 'ACTIVA' ? 'ACTIVE' : null);
  if (license && input.device_id && activationStatus !== 'ACTIVE') {
    finalDecision = {
      status: 'invalid',
      can_access: false,
      reason: 'device_not_activated_for_license'
    };
  }

  response.status = ALLOWED_OUTPUT_STATUS.has(finalDecision.status) ? finalDecision.status : 'invalid';
  response.can_access = Boolean(finalDecision.can_access);
  response.reason = finalDecision.reason || 'validation_result';

  response.company = subscription?.company_id
    ? { id: subscription.company_id, name: subscription.company_name || null }
    : license?.company_id
      ? { id: license.company_id, name: null }
      : null;

  response.product = (subscription?.product_id || license?.product_id)
    ? {
        id: subscription?.product_id || license?.product_id,
        slug: subscription?.product_slug || license?.product_slug || null,
        name: subscription?.product_name || license?.product_name || null
      }
    : null;

  response.project = (subscription?.project_id || license?.project_id)
    ? {
        id: subscription?.project_id || license?.project_id,
        code: subscription?.project_code || license?.project_code || null,
        name: subscription?.project_name || license?.project_name || null
      }
    : null;

  response.plan = mapPlanCore(subscription);
  response.subscription = mapSubscriptionCore(subscription);
  response.license = mapLicenseCore(license);
  response.limits = {
    max_devices: Number(subscription?.device_limit ?? license?.max_dispositivos ?? 0) || null,
    used_devices: usedDevices,
    company_limit: Number(subscription?.company_limit ?? 0) || null
  };
  response.offline_grace_until = license?.offline_grace_until || null;

  if (!license && !subscription) {
    response.status = 'not_found';
    response.can_access = false;
    response.reason = 'license_or_subscription_not_found';
  }

  await maybeWriteValidationAudit({ req, input, response, license, subscription });
  return response;
}

async function maybeWriteValidationAudit({ req, input, response, license, subscription }) {
  const companyId = subscription?.company_id || license?.company_id || input.company_id || null;
  const licenseId = license?.id || null;
  if (!companyId && !licenseId) return;

  const targetType = licenseId ? 'license' : 'company';
  const targetId = licenseId || companyId;

  await auditLogService.log({
    company_id: companyId,
    product_id: subscription?.product_id || license?.product_id || input.product_id || null,
    project_id: subscription?.project_id || license?.project_id || input.project_id || null,
    target_type: targetType,
    target_id: targetId,
    action: 'license.v2_validate',
    after_data: {
      status: response.status,
      can_access: response.can_access,
      reason: response.reason,
      license_id: licenseId,
      subscription_id: subscription?.id || null,
      request: {
        company_id: input.company_id,
        business_id: input.business_id,
        product_id: input.product_id,
        project_id: input.project_id,
        device_id: input.device_id ? 'provided' : null,
        license_key: input.license_key ? maskLicenseKey(input.license_key) : null
      }
    }
  }, { req });
}

module.exports = {
  validateLicense
};