const passwordResetService = require('../services/passwordResetService');

async function createToken(req, res) {
  try {
    const { business_id, username } = req.body || {};
    const result = await passwordResetService.createSupportResetToken({
      businessId: business_id,
      username,
      issuedBy: req.adminUser
    });

    return res.json({
      ok: true,
      token: result.token,
      ttl_minutes: result.ttlMinutes,
      expires_at: result.expiresAt
    });
  } catch (error) {
    const status = Number(error && error.status) || 500;
    const message = String(error && error.message ? error.message : 'Error interno del servidor');
    if (status >= 500) {
      console.error('adminSupportReset.createToken error:', error);
    }
    return res.status(status).json({ ok: false, message });
  }
}

module.exports = {
  createToken
};
