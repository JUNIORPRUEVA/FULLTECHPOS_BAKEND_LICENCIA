const metaAdsService = require('../services/metaAdsService');

async function getConfig(req, res) {
  try {
    const config = await metaAdsService.getMetaAdsConfigForAdmin();
    return res.json({ ok: true, config });
  } catch (error) {
    console.error('adminMetaAds.getConfig error:', error.message || error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function updateConfig(req, res) {
  try {
    const config = await metaAdsService.updateMetaAdsConfig(req.body || {});
    return res.json({ ok: true, config });
  } catch (error) {
    const status = Number(error && error.statusCode) || 500;
    if (status >= 500) {
      console.error('adminMetaAds.updateConfig error:', error.message || error);
    }
    return res.status(status).json({ ok: false, message: error.message || 'Error interno del servidor' });
  }
}

async function testConnection(req, res) {
  try {
    const result = await metaAdsService.testMetaAdsConnection();
    return res.json({ ok: result.ok, ...result });
  } catch (error) {
    const status = Number(error && error.statusCode) || 500;
    if (status >= 500) {
      console.error('adminMetaAds.testConnection error:', error.message || error);
    }
    return res.status(status).json({
      ok: false,
      message: error.message || 'Error interno del servidor',
      graph_error: error.graphError || null,
    });
  }
}

async function createCampaign(req, res) {
  try {
    const result = await metaAdsService.createMetaAdsCampaign(req.body || {});
    return res.json(result);
  } catch (error) {
    const status = Number(error && error.statusCode) || 500;
    if (status >= 500) {
      console.error('adminMetaAds.createCampaign error:', error.message || error);
    }
    return res.status(status).json({
      ok: false,
      message: error.message || 'Error creando campaña',
      graph_error: error.graphError || null,
    });
  }
}

module.exports = {
  getConfig,
  updateConfig,
  testConnection,
  createCampaign,
};
