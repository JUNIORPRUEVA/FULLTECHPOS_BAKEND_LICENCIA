const settingsModel = require('../models/storeSettingsModel');

async function getSettings(req, res) {
  try {
    const settings = await settingsModel.getSettings();
    return res.json({ ok: true, settings });
  } catch (e) {
    console.error('admin getSettings error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function updateSettings(req, res) {
  try {
    const patch = req.body || {};
    const updated = await settingsModel.updateSettings({
      brand_name: patch.brand_name,
      logo_url: patch.logo_url,
      whatsapp: patch.whatsapp,
      email: patch.email,
      address: patch.address,
      socials: patch.socials,
      theme: patch.theme
    });
    return res.json({ ok: true, settings: updated });
  } catch (e) {
    console.error('admin updateSettings error:', e);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

module.exports = {
  getSettings,
  updateSettings
};
