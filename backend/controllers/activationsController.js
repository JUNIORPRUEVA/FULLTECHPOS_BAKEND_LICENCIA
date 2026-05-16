const activationService = require('../services/activationService');

function sendError(res, error) {
  const status = error.statusCode || 500;
  if (status >= 500) console.error('activationsController error:', error);
  return res.status(status).json({
    ok: false,
    code: error.code || 'INTERNAL_ERROR',
    message: error.message || 'Error interno del servidor'
  });
}

async function activate(req, res) {
  try {
    const result = await activationService.activate(req.body || {}, { req });
    return res.status(201).json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

async function heartbeat(req, res) {
  try {
    const result = await activationService.heartbeat(req.body || {}, { req });
    return res.json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

async function revoke(req, res) {
  try {
    const result = await activationService.revoke(req.body || {}, { req });
    return res.json(result);
  } catch (error) {
    return sendError(res, error);
  }
}

module.exports = {
  activate,
  heartbeat,
  revoke
};
