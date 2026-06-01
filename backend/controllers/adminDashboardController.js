const { pool } = require('../db/pool');

/**
 * GET /api/admin/dashboard-stats
 * Returns real metrics for the dashboard based on currently active modules.
 * Only returns data for: customers, licenses, projects, payments.
 * Does NOT return fake or irrelevant data for non-existent modules.
 */
async function getDashboardStats(req, res) {
  try {
    // Run all queries in parallel for performance
    const [
      customersResult,
      licensesResult,
      activeLicensesResult,
      expiredLicensesResult,
      pendingLicensesResult,
      blockedLicensesResult,
      projectsResult,
      paymentsResult,
      pendingPaymentsResult,
      completedPaymentsResult,
    ] = await Promise.allSettled([
      pool.query('SELECT COUNT(*)::int AS total FROM customers'),
      pool.query('SELECT COUNT(*)::int AS total FROM licenses WHERE estado::text != \'ELIMINADA\''),
      pool.query('SELECT COUNT(*)::int AS total FROM licenses WHERE estado::text = \'ACTIVA\''),
      pool.query('SELECT COUNT(*)::int AS total FROM licenses WHERE estado::text = \'VENCIDA\''),
      pool.query('SELECT COUNT(*)::int AS total FROM licenses WHERE estado::text = \'PENDIENTE\''),
      pool.query('SELECT COUNT(*)::int AS total FROM licenses WHERE estado::text = \'BLOQUEADA\''),
      pool.query('SELECT COUNT(*)::int AS total FROM projects'),
      pool.query('SELECT COUNT(*)::int AS total FROM payments'),
      pool.query('SELECT COUNT(*)::int AS total FROM payments WHERE estado::text = \'PENDIENTE\''),
      pool.query('SELECT COUNT(*)::int AS total FROM payments WHERE estado::text = \'COMPLETADO\''),
    ]);

    const safeValue = (result, defaultValue = 0) => {
      if (result.status === 'fulfilled' && result.value?.rows?.[0]) {
        return result.value.rows[0].total ?? defaultValue;
      }
      return defaultValue;
    };

    const stats = {
      customers: {
        total: safeValue(customersResult),
      },
      licenses: {
        total: safeValue(licensesResult),
        active: safeValue(activeLicensesResult),
        expired: safeValue(expiredLicensesResult),
        pending: safeValue(pendingLicensesResult),
        blocked: safeValue(blockedLicensesResult),
      },
      projects: {
        total: safeValue(projectsResult),
      },
      payments: {
        total: safeValue(paymentsResult),
        pending: safeValue(pendingPaymentsResult),
        completed: safeValue(completedPaymentsResult),
      },
    };

    return res.json({
      ok: true,
      data: stats,
    });
  } catch (error) {
    console.error('[dashboardStats] Error:', error);
    return res.status(500).json({
      ok: false,
      message: 'Error al obtener estadísticas del dashboard',
    });
  }
}

module.exports = {
  getDashboardStats,
};
