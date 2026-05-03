const { pool } = require('../db/pool');

const platformUsersModel = require('../models/platformUsersModel');
const rolesModel = require('../models/rolesModel');
const auditLogService = require('../services/auditLogService');

function asUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

async function listPlatformUsers(req, res) {
  try {
    const data = await platformUsersModel.list({
      status: req.query.status ? String(req.query.status).trim().toLowerCase() : undefined,
      user_type: req.query.user_type ? String(req.query.user_type).trim().toLowerCase() : undefined,
      q: req.query.q ? String(req.query.q) : undefined,
      limit: Math.min(200, Math.max(1, Number(req.query.limit) || 50)),
      offset: Math.max(0, Number(req.query.offset) || 0)
    });
    return res.json({ ok: true, ...data });
  } catch (error) {
    console.error('listPlatformUsers error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

async function createPlatformUser(req, res) {
  try {
    const user = await platformUsersModel.create(req.body || {});
    await auditLogService.log({
      target_type: 'user',
      target_id: user.id,
      action: 'platform_user.create',
      after_data: user
    }, { req });
    return res.status(201).json({ ok: true, user });
  } catch (error) {
    const code = String(error?.code || '');
    const message = String(error?.message || 'Error interno');
    return res.status(code === '23505' ? 409 : 400).json({ ok: false, message });
  }
}

async function assignRole(req, res) {
  const client = await pool.connect();
  try {
    const userId = asUuid(req.params.id);
    const roleId = asUuid(req.body?.role_id);
    const companyId = req.body?.company_id == null ? null : asUuid(req.body.company_id);
    if (!userId) return res.status(400).json({ ok: false, message: 'id inválido' });
    if (!roleId) return res.status(400).json({ ok: false, message: 'role_id inválido' });
    if (req.body?.company_id != null && !companyId) {
      return res.status(400).json({ ok: false, message: 'company_id inválido' });
    }

    await client.query('BEGIN');

    const user = await platformUsersModel.getById(userId, { client });
    if (!user) {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Usuario no encontrado' });
    }
    const role = await rolesModel.getRoleById(roleId, { client });
    if (!role) {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, message: 'Rol no encontrado' });
    }
    if (companyId) {
      const companyRes = await client.query('SELECT id FROM companies WHERE id = $1', [companyId]);
      if (!companyRes.rows[0]) {
        await client.query('ROLLBACK');
        return res.status(404).json({ ok: false, message: 'Company no encontrada' });
      }
    }

    const assignment = await platformUsersModel.assignRole({ user_id: userId, role_id: roleId, company_id: companyId }, { client });
    await auditLogService.log({
      company_id: companyId,
      target_type: 'user',
      target_id: userId,
      action: 'platform_user.assign_role',
      after_data: { assignment, role }
    }, { client, req });

    await client.query('COMMIT');
    return res.status(201).json({ ok: true, assignment });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('assignRole error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  } finally {
    client.release();
  }
}

module.exports = {
  listPlatformUsers,
  createPlatformUser,
  assignRole
};