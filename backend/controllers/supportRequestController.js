const supportRequestService = require('../services/supportRequestService');

async function requestSupport(req, res) {
  try {
    const {
      business_id,
      username,
      business_name,
      owner_name,
      phone,
      email,
      message
    } = req.body || {};

    const result = await supportRequestService.sendSupportMessage({
      businessId: business_id,
      username,
      businessName: business_name,
      ownerName: owner_name,
      phone,
      email,
      message
    });

    return res.json({
      ok: true,
      status: result.provider_status,
      message: 'Tu mensaje fue enviado. Mantente pendiente a la respuesta de soporte.'
    });
  } catch (error) {
    const status = Number(error && error.status) || 500;
    const message = String(error && error.message ? error.message : 'Error interno del servidor');
    if (status >= 500) {
      console.error('supportRequest.requestSupport error:', error);
    }
    return res.status(status).json({ ok: false, message });
  }
}

module.exports = {
  requestSupport
};
