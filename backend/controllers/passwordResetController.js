const passwordResetService = require('../services/passwordResetService');

async function requestCode(req, res) {
  try {
    const { business_id, username } = req.body || {};
    const result = await passwordResetService.createResetRequest({
      businessId: business_id,
      username
    });

    return res.json({
      ok: true,
      request_id: result.requestId,
      expires_at: result.expiresAt,
      ttl_minutes: result.ttlMinutes
    });
  } catch (error) {
    const status = Number(error && error.status) || 500;
    const message = String(error && error.message ? error.message : 'Error interno del servidor');
    if (status >= 500) {
      console.error('passwordReset.requestCode error:', error);
    }
    return res.status(status).json({ ok: false, message });
  }
}

async function confirmCode(req, res) {
  try {
    const { business_id, username, request_id, code } = req.body || {};
    const result = await passwordResetService.confirmResetCode({
      businessId: business_id,
      username,
      requestId: request_id,
      code
    });

    return res.json({
      ok: true,
      reset_proof: result.resetProof,
      expires_in: result.expiresIn
    });
  } catch (error) {
    const status = Number(error && error.status) || 500;
    const message = String(error && error.message ? error.message : 'Error interno del servidor');
    if (status >= 500) {
      console.error('passwordReset.confirmCode error:', error);
    }
    return res.status(status).json({ ok: false, message });
  }
}

async function confirmSupportToken(req, res) {
  try {
    const { business_id, username, token } = req.body || {};
    const result = await passwordResetService.confirmSupportToken({
      businessId: business_id,
      username,
      token
    });

    return res.json({
      ok: true,
      reset_proof: result.resetProof,
      expires_in: result.expiresIn
    });
  } catch (error) {
    const status = Number(error && error.status) || 500;
    const message = String(error && error.message ? error.message : 'Error interno del servidor');
    if (status >= 500) {
      console.error('passwordReset.confirmSupportToken error:', error);
    }
    return res.status(status).json({ ok: false, message });
  }
}

module.exports = {
  requestCode,
  confirmCode,
  confirmSupportToken
};
