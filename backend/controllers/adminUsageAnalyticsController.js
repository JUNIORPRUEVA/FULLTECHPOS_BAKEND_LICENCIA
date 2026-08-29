const usageAnalyticsModel = require('../models/usageAnalyticsModel');

async function overview(req, res) {
  try {
    const overview = await usageAnalyticsModel.getOverview(req.query || {});
    return res.json({ ok: true, overview });
  } catch (error) {
    console.error('admin usage overview error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function accounts(req, res) {
  try {
    const result = await usageAnalyticsModel.listAccounts(req.query || {});
    return res.json({ ok: true, ...result });
  } catch (error) {
    console.error('admin usage accounts error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function events(req, res) {
  try {
    const result = await usageAnalyticsModel.listEvents(req.query || {});
    return res.json({ ok: true, ...result });
  } catch (error) {
    console.error('admin usage events error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  overview,
  accounts,
  events
};
