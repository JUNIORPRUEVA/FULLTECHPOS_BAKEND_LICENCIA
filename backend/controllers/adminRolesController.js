const rolesModel = require('../models/rolesModel');

async function listRoles(req, res) {
  try {
    const roles = await rolesModel.listRoles();
    return res.json({ ok: true, roles });
  } catch (error) {
    console.error('listRoles error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function listPermissions(req, res) {
  try {
    const permissions = await rolesModel.listPermissions();
    return res.json({ ok: true, permissions });
  } catch (error) {
    console.error('listPermissions error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

module.exports = {
  listRoles,
  listPermissions
};