const { pool } = require('../db/pool');
const auditLogService = require('./auditLogService');

const ACTIVE_STATUS = 'ACTIVE';
const PENDING_PAYMENT_STATUS = 'PENDING_PAYMENT';
const GRACE_STATUS = 'GRACE';
const EXPIRED_STATUS = 'EXPIRED';
const CANCELLED_STATUS = 'CANCELLED';

const STATUS_ALIASES = {
  trial: ACTIVE_STATUS,
  active: ACTIVE_STATUS,
  lifetime: ACTIVE_STATUS,
  past_due: PENDING_PAYMENT_STATUS,
  suspended: EXPIRED_STATUS,
  expired: EXPIRED_STATUS,
  cancelled: CANCELLED_STATUS
};

function normalizeStatus(status) {
  const raw = String(status || '').trim();
  if (!raw) return ACTIVE_STATUS;
  const upper = raw.toUpperCase();
  if ([ACTIVE_STATUS, PENDING_PAYMENT_STATUS, GRACE_STATUS, EXPIRED_STATUS, CANCELLED_STATUS].includes(upper)) {
    return upper;
  }
  return STATUS_ALIASES[raw.toLowerCase()] || ACTIVE_STATUS;
}

function startOfUtcDay(date) {
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

function calculateDaysLate(dueDate, now = new Date()) {
  if (!dueDate) return 0;
  const due = new Date(dueDate);
  if (Number.isNaN(due.getTime())) return 0;
  return Math.floor((startOfUtcDay(now) - startOfUtcDay(due)) / (24 * 60 * 60 * 1000));
}

function resolveStatusFromDueDate(subscription, now = new Date()) {
  const current = normalizeStatus(subscription.status);
  if (current === CANCELLED_STATUS) return CANCELLED_STATUS;
  if (String(subscription.license_type || '').toUpperCase() === 'PERMANENTE') return ACTIVE_STATUS;

  const dueDate = subscription.next_payment_date || subscription.renewal_date || subscription.end_date;
  const daysLate = calculateDaysLate(dueDate, now);

  if (daysLate > 10) return EXPIRED_STATUS;
  if (daysLate > 5) return GRACE_STATUS;
  if (daysLate > 0) return PENDING_PAYMENT_STATUS;
  return ACTIVE_STATUS;
}

async function fetchSubscriptionsForStatusUpdate(client) {
  const res = await client.query(
    `SELECT id, company_id, customer_id, license_id, product_id, project_id, status,
            license_type, next_payment_date, renewal_date, end_date
     FROM company_subscriptions
     WHERE UPPER(status) <> 'CANCELLED'
     ORDER BY COALESCE(next_payment_date, renewal_date, end_date, created_at) ASC`
  );
  return res.rows;
}

async function patchSubscriptionStatus(subscription, nextStatus, client) {
  const res = await client.query(
    `UPDATE company_subscriptions
     SET status = $2,
         updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [subscription.id, nextStatus]
  );
  return res.rows[0] || null;
}

async function syncLinkedLicenses(subscription, nextStatus, client) {
  const shouldBlock = nextStatus === EXPIRED_STATUS || nextStatus === CANCELLED_STATUS;
  const shouldActivate = nextStatus === ACTIVE_STATUS;
  if (!shouldBlock && !shouldActivate) return [];

  const licenseIds = [];
  if (subscription.license_id) licenseIds.push(subscription.license_id);

  const status = shouldBlock ? 'BLOQUEADA' : 'ACTIVA';
  const res = await client.query(
    `UPDATE licenses
     SET estado = $2,
         license_type = COALESCE(license_type, 'SUSCRIPCION')
     WHERE (subscription_id = $1 OR id = ANY($3::uuid[]))
       AND license_type <> 'PERMANENTE'
       AND estado <> $2
     RETURNING id, license_key, company_id, customer_id, subscription_id, estado`,
    [subscription.id, status, licenseIds]
  );
  return res.rows;
}

async function ensurePermanentLicensesActive(client) {
  const res = await client.query(
    `UPDATE licenses
     SET estado = 'ACTIVA',
         fecha_fin = NULL,
         expires_at = NULL
     WHERE license_type = 'PERMANENTE'
       AND estado <> 'ACTIVA'
     RETURNING id, license_key, company_id, customer_id`
  );
  return res.rows;
}

async function updateSubscriptionStatus(subscriptionId = null, options = {}) {
  const client = options.client || await pool.connect();
  const ownsClient = !options.client;

  try {
    if (ownsClient) await client.query('BEGIN');

    const { req } = options;
    const now = options.now || new Date();
    const subscriptions = subscriptionId
      ? (await client.query(
          `SELECT id, company_id, customer_id, license_id, product_id, project_id, status,
                  license_type, next_payment_date, renewal_date, end_date
           FROM company_subscriptions
           WHERE id = $1`,
          [subscriptionId]
        )).rows
      : await fetchSubscriptionsForStatusUpdate(client);

    let activeCount = 0;
    let pendingPaymentCount = 0;
    let graceCount = 0;
    let expiredCount = 0;
    let cancelledCount = 0;
    let skippedCount = 0;
    let licensesActivatedCount = 0;
    let licensesBlockedCount = 0;

    for (const subscription of subscriptions) {
      const previousStatus = normalizeStatus(subscription.status);
      const nextStatus = resolveStatusFromDueDate(subscription, now);

      if (nextStatus === ACTIVE_STATUS) activeCount++;
      else if (nextStatus === PENDING_PAYMENT_STATUS) pendingPaymentCount++;
      else if (nextStatus === GRACE_STATUS) graceCount++;
      else if (nextStatus === EXPIRED_STATUS) expiredCount++;
      else if (nextStatus === CANCELLED_STATUS) cancelledCount++;

      const changed = previousStatus !== nextStatus || subscription.status !== nextStatus;
      const updated = changed ? await patchSubscriptionStatus(subscription, nextStatus, client) : subscription;
      if (!updated) {
        skippedCount++;
        continue;
      }

      if (changed) {
        await auditLogService.log(
          {
            company_id: subscription.company_id,
            product_id: subscription.product_id || null,
            project_id: subscription.project_id || null,
            target_type: 'subscription',
            target_id: subscription.id,
            action: 'subscription.status_auto_update',
            before_data: { status: subscription.status, next_payment_date: subscription.next_payment_date },
            after_data: { status: nextStatus }
          },
          { client, req }
        );
      }

      const affectedLicenses = await syncLinkedLicenses(updated, nextStatus, client);
      if (nextStatus === ACTIVE_STATUS) licensesActivatedCount += affectedLicenses.length;
      if (nextStatus === EXPIRED_STATUS || nextStatus === CANCELLED_STATUS) licensesBlockedCount += affectedLicenses.length;

      for (const license of affectedLicenses) {
        await auditLogService.log(
          {
            company_id: license.company_id || subscription.company_id,
            target_type: 'license',
            target_id: license.id,
            action: 'license.subscription_sync',
            before_data: { subscription_id: subscription.id },
            after_data: { estado: license.estado, subscription_status: nextStatus }
          },
          { client, req }
        );
      }
    }

    const permanentLicenses = await ensurePermanentLicensesActive(client);

    const result = {
      subscriptions_checked: subscriptions.length,
      active_count: activeCount,
      pending_payment_count: pendingPaymentCount,
      grace_count: graceCount,
      expired_count: expiredCount,
      cancelled_count: cancelledCount,
      skipped_count: skippedCount,
      licenses_activated_count: licensesActivatedCount,
      licenses_blocked_count: licensesBlockedCount,
      permanent_licenses_activated_count: permanentLicenses.length
    };

    if (!subscriptionId) {
      await auditLogService.log(
        {
          target_type: 'other',
          target_id: 'maintenance-run',
          action: 'maintenance.run',
          after_data: result
        },
        { client, req }
      );
    }

    if (ownsClient) await client.query('COMMIT');
    return result;
  } catch (error) {
    if (ownsClient) await client.query('ROLLBACK');
    throw error;
  } finally {
    if (ownsClient) client.release();
  }
}

async function runMaintenance(options = {}) {
  return updateSubscriptionStatus(null, options);
}

module.exports = {
  updateSubscriptionStatus,
  runMaintenance
};
