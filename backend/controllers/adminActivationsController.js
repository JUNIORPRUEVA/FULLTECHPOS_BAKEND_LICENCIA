const activationsModel = require('../models/activationsModel');
const auditLogService = require('../services/auditLogService');

const STATUS_ALIASES = {
  ACTIVA: 'ACTIVE',
  ACTIVE: 'ACTIVE',
  BLOQUEADA: 'BLOCKED',
  BLOCKED: 'BLOCKED',
  REVOCADA: 'REVOKED',
  REVOKED: 'REVOKED'
};

function parsePagination(req) {
  const pageRaw = req.query.page;
  const limitRaw = req.query.limit;
  const page = Math.max(1, Number(pageRaw || 1) || 1);
  const limit = Math.min(200, Math.max(1, Number(limitRaw || 50) || 50));
  const offset = (page - 1) * limit;
  return { page, limit, offset };
}

function normalizeStatus(value) {
  if (!value) return undefined;
  return STATUS_ALIASES[String(value).trim().toUpperCase()] || null;
}

async function listActivations(req, res) {
  try {
    const { page, limit, offset } = parsePagination(req);
    const license_id = req.query.license_id || undefined;
    const device_id = req.query.device_id || undefined;
    const rawStatus = req.query.status || req.query.estado;
    const status = normalizeStatus(rawStatus);

    if (rawStatus && !status) {
      return res.status(400).json({ ok: false, message: 'status inválido. Use: ACTIVE|BLOCKED|REVOKED' });
    }

    const { total, activations } = await activationsModel.listActivations({
      limit,
      offset,
      license_id,
      device_id,
      status
    });

    return res.json({ ok: true, page, limit, total, activations });
  } catch (error) {
    console.error('admin listActivations error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function getActivation(req, res) {
  try {
    const activation = await activationsModel.getById(req.params.id);
    if (!activation) {
      return res.status(404).json({ ok: false, message: 'Activación no encontrada' });
    }
    return res.json({ ok: true, activation });
  } catch (error) {
    console.error('admin getActivation error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function revokeActivation(req, res) {
  try {
    const activationId = req.params.id;
    const updated = await activationsModel.revokeActivation(activationId);
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Activación no encontrada' });
    }

    await auditLogService.log({
      target_type: 'activation',
      target_id: updated.id,
      action: 'activation.revoke_admin',
      after_data: { status: updated.status }
    }, { req });

    return res.json({ ok: true, activation: updated });
  } catch (error) {
    console.error('admin revokeActivation error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function blockActivation(req, res) {
  try {
    const activationId = req.params.id;
    const updated = await activationsModel.blockActivation(activationId);
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Activación no encontrada' });
    }

    await auditLogService.log({
      target_type: 'activation',
      target_id: updated.id,
      action: 'activation.block_admin',
      after_data: { status: updated.status }
    }, { req });

    return res.json({ ok: true, activation: updated });
  } catch (error) {
    console.error('admin blockActivation error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

async function activateActivation(req, res) {
  try {
    const activationId = req.params.id;
    const updated = await activationsModel.updateStatus(activationId, 'ACTIVE');
    if (!updated) {
      return res.status(404).json({ ok: false, message: 'Activación no encontrada' });
    }

    await auditLogService.log({
      target_type: 'activation',
      target_id: updated.id,
      action: 'activation.activate_admin',
      after_data: { status: updated.status }
    }, { req });

    return res.json({ ok: true, activation: updated });
  } catch (error) {
    console.error('admin activateActivation error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  listActivations,
  getActivation,
  revokeActivation,
  blockActivation,
  activateActivation
};
