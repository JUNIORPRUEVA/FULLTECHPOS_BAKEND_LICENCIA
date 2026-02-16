const evolutionConfigService = require('../services/evolutionConfigService');

async function getConfig(req, res) {
  try {
    const config = await evolutionConfigService.getEvolutionConfigForAdmin();
    return res.json({ ok: true, config });
  } catch (error) {
    console.error('adminEvolution.getConfig error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function updateConfig(req, res) {
  try {
    const payload = req.body || {};
    const config = await evolutionConfigService.updateEvolutionConfig(payload);
    return res.json({ ok: true, config });
  } catch (error) {
    const message = String(error && error.message ? error.message : 'Error interno del servidor');
    const status =
      message.includes('requerido') || message.includes('incompleta')
        ? 400
        : 500;
    if (status >= 500) {
      console.error('adminEvolution.updateConfig error:', error);
    }
    return res.status(status).json({ ok: false, message });
  }
}

module.exports = {
  getConfig,
  updateConfig
};
