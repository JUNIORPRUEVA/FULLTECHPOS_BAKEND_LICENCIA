const usageAnalyticsService = require('../services/usageAnalyticsService');

function sendError(res, error) {
  const status = error.statusCode || 500;
  if (status >= 500) console.error('usageAnalyticsController error:', error);
  return res.status(status).json({
    ok: false,
    code: error.code || 'INTERNAL_ERROR',
    message: error.message || 'Error interno del servidor'
  });
}

async function heartbeat(req, res) {
  try {
    const result = await usageAnalyticsService.ingest({
      ...(req.body || {}),
      event_type: req.body?.event_type || 'app_heartbeat'
    }, { req });
    return res.status(202).json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

async function event(req, res) {
  try {
    const result = await usageAnalyticsService.ingest(req.body || {}, { req });
    return res.status(202).json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

async function batch(req, res) {
  try {
    const result = await usageAnalyticsService.ingestBatch(req.body || {}, { req });
    return res.status(202).json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

module.exports = {
  heartbeat,
  event,
  batch
};
