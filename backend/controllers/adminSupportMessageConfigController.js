const supportMessageConfigService = require('../services/supportMessageConfigService');

async function getConfig(req, res) {
  try {
    const config = await supportMessageConfigService.getSupportMessageConfigForAdmin();
    return res.json({ ok: true, config });
  } catch (error) {
    console.error('adminSupportMessageConfig.getConfig error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function updateConfig(req, res) {
  try {
    const payload = req.body || {};
    const config = await supportMessageConfigService.updateSupportMessageConfig(payload);
    return res.json({ ok: true, config });
  } catch (error) {
    const message = String(error && error.message ? error.message : 'Error interno del servidor');
    const status =
      message.includes('requerido') || message.includes('incompleta')
        ? 400
        : 500;
    if (status >= 500) {
      console.error('adminSupportMessageConfig.updateConfig error:', error);
    }
    return res.status(status).json({ ok: false, message });
  }
}

module.exports = {
  getConfig,
  updateConfig
};
