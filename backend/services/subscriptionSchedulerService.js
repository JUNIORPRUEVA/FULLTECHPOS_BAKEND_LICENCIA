const maintenanceService = require('./subscriptionMaintenanceService');

const DAY_MS = 24 * 60 * 60 * 1000;

function nextDailyDelay(hourUtc) {
  const now = new Date();
  const next = new Date(now);
  next.setUTCHours(hourUtc, 0, 0, 0);
  if (next.getTime() <= now.getTime()) {
    next.setUTCDate(next.getUTCDate() + 1);
  }
  return next.getTime() - now.getTime();
}

function startDailySubscriptionMaintenanceJob(options = {}) {
  const enabled = String(process.env.SAAS_MAINTENANCE_JOB_ENABLED || '1').trim() !== '0';
  if (!enabled) {
    console.log('[saas-maintenance] Job diario deshabilitado por SAAS_MAINTENANCE_JOB_ENABLED=0');
    return null;
  }

  const hourUtc = Math.max(0, Math.min(23, Number(process.env.SAAS_MAINTENANCE_HOUR_UTC || options.hourUtc || 5)));
  let running = false;

  async function runJob() {
    if (running) return;
    running = true;
    try {
      const result = await maintenanceService.runMaintenance({ source: 'daily-job' });
      console.log('[saas-maintenance] Job diario completado:', result);
    } catch (error) {
      console.error('[saas-maintenance] Error ejecutando job diario:', error?.message || error);
    } finally {
      running = false;
    }
  }

  const firstDelay = nextDailyDelay(hourUtc);
  const timeout = setTimeout(() => {
    runJob();
    const interval = setInterval(runJob, DAY_MS);
    if (typeof interval.unref === 'function') interval.unref();
  }, firstDelay);

  if (typeof timeout.unref === 'function') timeout.unref();

  if (String(process.env.SAAS_MAINTENANCE_RUN_ON_START || '').trim() === '1') {
    runJob();
  }

  console.log(`[saas-maintenance] Job diario programado a las ${String(hourUtc).padStart(2, '0')}:00 UTC`);
  return { runNow: runJob };
}

module.exports = { startDailySubscriptionMaintenanceJob };
