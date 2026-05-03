/**
 * adminMaintenanceController.js
 * Phase 5 – Triggers subscription maintenance via a protected admin endpoint.
 */

const maintenanceService = require('../services/subscriptionMaintenanceService');

async function runMaintenance(req, res) {
  try {
    const result = await maintenanceService.runMaintenance({ req });

    return res.json({
      ok: true,
      data: result,
      message: `Mantenimiento completado. ${result.expired_count} expiradas, ${result.past_due_count} en mora, ${result.licenses_blocked_count} licencias bloqueadas.`
    });
  } catch (err) {
    console.error('[maintenance] runMaintenance error:', err);
    return res.status(500).json({ ok: false, error: 'Error al ejecutar mantenimiento', detail: err.message });
  }
}

module.exports = { runMaintenance };
