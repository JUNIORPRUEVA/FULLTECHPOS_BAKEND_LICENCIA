/**
 * subscriptionMaintenanceService.js
 * Phase 5 – subscription auto-expire, grace/past_due detection, and license sync.
 *
 * Rules:
 *  - status IN ('active','trial','past_due') AND end_date < NOW()
 *      → grace_until IS NULL OR grace_until < NOW()  ⇒ 'expired'
 *      → grace_until >= NOW()                        ⇒ 'past_due'
 *  - 'suspended' and 'cancelled' are never touched by maintenance.
 *
 * After each subscription status change, linked licenses are updated:
 *  - expired / suspended / cancelled  ⇒ license.estado ACTIVA → VENCIDA
 *  - active / trial / past_due / lifetime ⇒ leave licenses as-is
 *    (reactivation is done manually by admin; maintenance never reactivates)
 *
 * Audit log is written for every subscription change and every license change.
 */

const { pool } = require('../db/pool');
const auditLogService = require('./auditLogService');

// Statuses that are eligible for automated expiry checks.
const CHECKABLE_STATUSES = ['active', 'trial', 'past_due'];

// Statuses that block access – licenses must be blocked when sub is in these.
const BLOCKING_STATUSES = new Set(['expired', 'suspended', 'cancelled']);

/**
 * Find all subscriptions that have passed end_date and whose status is still
 * in CHECKABLE_STATUSES. Returns plain DB rows (no joins needed here).
 */
async function fetchExpiredCandidates(client) {
  const res = await client.query(
    `SELECT id, company_id, product_id, project_id, status, end_date, grace_until
     FROM company_subscriptions
     WHERE status = ANY($1)
       AND end_date IS NOT NULL
       AND end_date < NOW()
     ORDER BY end_date ASC`,
    [CHECKABLE_STATUSES]
  );
  return res.rows;
}

/**
 * Update a subscription status directly (lightweight patch – no full re-fetch).
 * Returns the updated row from RETURNING *.
 */
async function patchSubscriptionStatus(id, status, client) {
  const res = await client.query(
    `UPDATE company_subscriptions
     SET status = $2, updated_at = now()
     WHERE id = $1
     RETURNING *`,
    [id, status]
  );
  return res.rows[0] || null;
}

/**
 * Sync licenses linked to a subscription.
 * If the new status blocks access, set ACTIVA licenses to VENCIDA.
 * Never deletes licenses. Never reactivates.
 * Returns the list of license ids that were changed.
 */
async function syncLinkedLicenses(subscriptionId, newStatus, client) {
  if (!BLOCKING_STATUSES.has(newStatus)) return [];

  const res = await client.query(
    `UPDATE licenses
     SET estado = 'VENCIDA'
     WHERE subscription_id = $1
       AND estado = 'ACTIVA'
     RETURNING id, license_key, company_id, subscription_id`,
    [subscriptionId]
  );
  return res.rows;
}

/**
 * Core maintenance logic – runs inside a single DB transaction.
 * Returns { expired_count, past_due_count, skipped_count, licenses_blocked_count }
 */
async function runMaintenanceTransaction(client, options = {}) {
  const { req } = options;

  const candidates = await fetchExpiredCandidates(client);

  let expiredCount = 0;
  let pastDueCount = 0;
  let skippedCount = 0;
  let licensesBlockedCount = 0;
  const now = new Date();

  for (const sub of candidates) {
    const gracePassed =
      sub.grace_until == null || new Date(sub.grace_until).getTime() < now.getTime();

    const newStatus = gracePassed ? 'expired' : 'past_due';

    // If the sub is already in the target status, skip (handles past_due → past_due).
    if (sub.status === newStatus) {
      skippedCount++;
      continue;
    }

    const prevStatus = sub.status;
    const updated = await patchSubscriptionStatus(sub.id, newStatus, client);
    if (!updated) {
      skippedCount++;
      continue;
    }

    // Audit log for the subscription status change.
    const auditAction =
      newStatus === 'expired'
        ? 'subscription.auto_expired'
        : 'subscription.entered_past_due';

    await auditLogService.log(
      {
        company_id: sub.company_id,
        product_id: sub.product_id || null,
        project_id: sub.project_id || null,
        target_type: 'subscription',
        target_id: sub.id,
        action: auditAction,
        before_data: { status: prevStatus, end_date: sub.end_date, grace_until: sub.grace_until },
        after_data: { status: newStatus }
      },
      { client, req }
    );

    if (newStatus === 'expired') expiredCount++;
    else pastDueCount++;

    // Sync licenses
    const affectedLicenses = await syncLinkedLicenses(sub.id, newStatus, client);
    licensesBlockedCount += affectedLicenses.length;

    for (const lic of affectedLicenses) {
      await auditLogService.log(
        {
          company_id: lic.company_id || sub.company_id,
          target_type: 'license',
          target_id: lic.id,
          action: 'license.access_changed',
          before_data: { estado: 'ACTIVA', subscription_id: sub.id },
          after_data: { estado: 'VENCIDA', reason: auditAction }
        },
        { client, req }
      );
    }
  }

  return {
    candidates_checked: candidates.length,
    expired_count: expiredCount,
    past_due_count: pastDueCount,
    skipped_count: skippedCount,
    licenses_blocked_count: licensesBlockedCount
  };
}

/**
 * Public entry point. Acquires a connection, wraps everything in a transaction.
 */
async function runMaintenance(options = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await runMaintenanceTransaction(client, options);

    // Write a single summary audit log for the maintenance run itself.
    await auditLogService.log(
      {
        target_type: 'other',
        target_id: 'maintenance-run',
        action: 'maintenance.run',
        after_data: result
      },
      { client, req: options.req }
    );

    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { runMaintenance };
