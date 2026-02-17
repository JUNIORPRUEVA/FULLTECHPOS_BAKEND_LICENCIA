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

module.exports = {
  confirmSupportToken
};
