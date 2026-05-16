/**
 * adminSaasDashboardController.js
 * Phase 5 – Serves GET /api/admin/saas-dashboard with all key SaaS metrics
 * computed server-side via aggregated SQL queries.
 */

const { pool } = require('../db/pool');

async function getDashboard(req, res) {
  try {
    const daysNearExpiration = Math.max(1, Math.min(90, Number(req.query.near_days) || 15));

    const [
      subscriptionCounts,
      pendingPayments,
      collectedThisMonth,
      monthlyEstimate,
      nearExpiration,
      revenueByOwnership,
      saasControlMetrics
    ] = await Promise.all([
      querySubscriptionCounts(),
      queryPendingPayments(),
      queryCollectedThisMonth(),
      queryMonthlyRevenueEstimate(),
      queryNearExpiration(daysNearExpiration),
      queryRevenueByOwnership(),
      querySaasControlMetrics()
    ]);

    return res.json({
      ok: true,
      data: {
        total_licenses: saasControlMetrics.total_licenses,
        active_licenses: saasControlMetrics.active_licenses,
        expired_licenses: saasControlMetrics.expired_licenses,
        pending_payments: saasControlMetrics.pending_payments,
        total_revenue: saasControlMetrics.total_revenue,
        customers_with_debt: saasControlMetrics.customers_with_debt,
        total_companies: subscriptionCounts.total_companies,
        active_subscriptions: subscriptionCounts.active,
        expired_subscriptions: subscriptionCounts.expired,
        suspended_subscriptions: subscriptionCounts.suspended,
        past_due_subscriptions: subscriptionCounts.past_due,
        grace_subscriptions: subscriptionCounts.grace,
        trial_subscriptions: subscriptionCounts.trial,
        lifetime_subscriptions: subscriptionCounts.lifetime,
        total_subscriptions: subscriptionCounts.total,
        pending_payment_records: pendingPayments,
        payments_collected_this_month: collectedThisMonth,
        monthly_revenue_estimate: monthlyEstimate,
        clients_near_expiration: nearExpiration,
        revenue_by_product_or_project: revenueByOwnership
      }
    });
  } catch (err) {
    console.error('[saas-dashboard] getDashboard error:', err);
    return res.status(500).json({ ok: false, error: 'Error al obtener dashboard', detail: err.message });
  }
}

// ─── helpers ──────────────────────────────────────────────────────────────────

async function querySubscriptionCounts() {
  const res = await pool.query(
    `SELECT
       COUNT(DISTINCT company_id)::int                                               AS total_companies,
       COUNT(*)::int                                                                  AS total,
       COUNT(*) FILTER (WHERE UPPER(status) = 'ACTIVE' OR status IN ('active','trial','lifetime'))::int AS active,
       COUNT(*) FILTER (WHERE UPPER(status) = 'EXPIRED' OR status IN ('expired','suspended'))::int AS expired,
       COUNT(*) FILTER (WHERE status = 'suspended')::int                            AS suspended,
       COUNT(*) FILTER (WHERE UPPER(status) = 'PENDING_PAYMENT' OR status = 'past_due')::int AS past_due,
       COUNT(*) FILTER (WHERE UPPER(status) = 'GRACE')::int                         AS grace,
       COUNT(*) FILTER (WHERE status = 'trial')::int                                AS trial,
       COUNT(*) FILTER (WHERE status = 'lifetime')::int                             AS lifetime
     FROM company_subscriptions`
  );
  return res.rows[0] || {};
}

async function queryPendingPayments() {
  const res = await pool.query(
    `SELECT COUNT(*)::int AS total FROM subscription_payments WHERE status = 'pending'`
  );
  return res.rows[0]?.total || 0;
}

async function queryCollectedThisMonth() {
  const res = await pool.query(
    `SELECT COALESCE(SUM(amount), 0)::numeric AS total
     FROM subscription_payments
     WHERE status = 'paid'
       AND paid_at >= date_trunc('month', now())
       AND paid_at < date_trunc('month', now()) + INTERVAL '1 month'`
  );
  return Number(res.rows[0]?.total || 0);
}

async function queryMonthlyRevenueEstimate() {
  // Monthly normalized estimate: monthly plans × price, annual / 12, lifetime / 24.
  // Only count active/trial/past_due/lifetime subscriptions.
  const res = await pool.query(
    `SELECT
       COALESCE(SUM(
         CASE pp.billing_period
           WHEN 'monthly'  THEN pp.price_amount
           WHEN 'annual'   THEN pp.price_amount / 12.0
           WHEN 'lifetime' THEN pp.price_amount / 24.0
           ELSE 0
         END
       ), 0)::numeric AS estimate
     FROM company_subscriptions cs
     INNER JOIN product_plans pp ON pp.id = cs.plan_id
      WHERE UPPER(cs.status) IN ('ACTIVE', 'PENDING_PAYMENT', 'GRACE')
        OR cs.status IN ('active', 'trial', 'past_due', 'lifetime')`
  );
  return Number(res.rows[0]?.estimate || 0);
}

async function queryNearExpiration(days) {
  const res = await pool.query(
    `SELECT cs.id, cs.company_id, c.name AS company_name,
            cs.status, cs.end_date, cs.grace_until,
            pp.name AS plan_name, pp.billing_period,
            p.name AS product_name, pr.name AS project_name
     FROM company_subscriptions cs
     INNER JOIN companies c ON c.id = cs.company_id
     INNER JOIN product_plans pp ON pp.id = cs.plan_id
     LEFT JOIN products p ON p.id = cs.product_id
     LEFT JOIN projects pr ON pr.id = cs.project_id
     WHERE (UPPER(cs.status) IN ('ACTIVE', 'PENDING_PAYMENT', 'GRACE') OR cs.status IN ('active', 'trial', 'past_due'))
       AND cs.end_date IS NOT NULL
       AND cs.end_date >= NOW()
       AND cs.end_date <= NOW() + ($1 || ' days')::interval
     ORDER BY cs.end_date ASC
     LIMIT 100`,
    [days]
  );
  return res.rows;
}

async function queryRevenueByOwnership() {
  const res = await pool.query(
    `SELECT
       COALESCE(p.name, pr.name, 'Unknown') AS label,
       CASE WHEN cs.product_id IS NOT NULL THEN 'product' ELSE 'project' END AS type,
       COUNT(cs.id)::int AS subscriptions,
       COALESCE(SUM(
         CASE pp.billing_period
           WHEN 'monthly'  THEN pp.price_amount
           WHEN 'annual'   THEN pp.price_amount / 12.0
           WHEN 'lifetime' THEN pp.price_amount / 24.0
           ELSE 0
         END
       ), 0)::numeric AS monthly_estimate
     FROM company_subscriptions cs
     INNER JOIN product_plans pp ON pp.id = cs.plan_id
     LEFT JOIN products p ON p.id = cs.product_id
     LEFT JOIN projects pr ON pr.id = cs.project_id
     WHERE UPPER(cs.status) IN ('ACTIVE', 'PENDING_PAYMENT', 'GRACE')
        OR cs.status IN ('active', 'trial', 'past_due', 'lifetime')
     GROUP BY 1, 2
     ORDER BY monthly_estimate DESC
     LIMIT 50`
  );
  return res.rows;
}

async function querySaasControlMetrics() {
  const res = await pool.query(
    `WITH license_metrics AS (
       SELECT
         COUNT(*)::int AS total_licenses,
         COUNT(*) FILTER (
           WHERE estado = 'ACTIVA'
             AND (
               license_type = 'PERMANENTE'
               OR COALESCE(expires_at, fecha_fin) IS NULL
               OR COALESCE(expires_at, fecha_fin) >= NOW()
             )
         )::int AS active_licenses,
         COUNT(*) FILTER (
           WHERE estado IN ('VENCIDA', 'BLOQUEADA')
              OR (license_type = 'SUSCRIPCION' AND COALESCE(expires_at, fecha_fin) IS NOT NULL AND COALESCE(expires_at, fecha_fin) < NOW())
         )::int AS expired_licenses
       FROM licenses
     ), debt_metrics AS (
       SELECT
         COUNT(*) FILTER (WHERE UPPER(cs.status) IN ('PENDING_PAYMENT', 'GRACE') OR cs.status = 'past_due')::int AS pending_subscriptions,
         COUNT(DISTINCT COALESCE(cs.customer_id::text, l.customer_id::text, cs.company_id::text)) FILTER (
           WHERE UPPER(cs.status) IN ('PENDING_PAYMENT', 'GRACE', 'EXPIRED') OR cs.status IN ('past_due', 'expired')
         )::int AS customers_with_debt
       FROM company_subscriptions cs
       LEFT JOIN licenses l ON l.id = cs.license_id OR l.subscription_id = cs.id
     ), payment_metrics AS (
       SELECT
         COUNT(*) FILTER (WHERE status = 'pending')::int AS pending_payment_records,
         COALESCE(SUM(amount) FILTER (WHERE status = 'paid'), 0)::numeric AS total_revenue
       FROM subscription_payments
     )
     SELECT
       lm.total_licenses,
       lm.active_licenses,
       lm.expired_licenses,
       (dm.pending_subscriptions + pm.pending_payment_records)::int AS pending_payments,
       pm.total_revenue,
       dm.customers_with_debt
     FROM license_metrics lm
     CROSS JOIN debt_metrics dm
     CROSS JOIN payment_metrics pm`
  );

  const row = res.rows[0] || {};
  return {
    total_licenses: Number(row.total_licenses || 0),
    active_licenses: Number(row.active_licenses || 0),
    expired_licenses: Number(row.expired_licenses || 0),
    pending_payments: Number(row.pending_payments || 0),
    total_revenue: Number(row.total_revenue || 0),
    customers_with_debt: Number(row.customers_with_debt || 0)
  };
}

module.exports = { getDashboard };
