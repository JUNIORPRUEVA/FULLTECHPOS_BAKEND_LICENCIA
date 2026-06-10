const passwordResetService = require('../services/passwordResetService');

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

/**
 * POST /api/password-reset/admin-token/validate
 * Valida y consume un token de reset generado por el admin para un cliente.
 * El cliente FULLPOS envía el token junto con su business_id para validar.
 */
async function validateAdminToken(req, res) {
  try {
    const { business_id, token } = req.body || {};
    const result = await passwordResetService.validateAdminToken({
      businessId: business_id,
      token
    });

    return res.json({
      ok: true,
      reset_proof: result.resetProof,
      expires_in: result.expiresIn,
      customer_id: result.customerId
    });
  } catch (error) {
    const status = Number(error && error.status) || 500;
    const message = String(error && error.message ? error.message : 'Error interno del servidor');
    if (status >= 500) {
      console.error('passwordReset.validateAdminToken error:', error);
    }
    return res.status(status).json({ ok: false, message });
  }
}

module.exports = {
  confirmSupportToken,
  validateAdminToken
};
