const activationsModel = require('../models/activationsModel');

function parsePagination(req) {
  const pageRaw = req.query.page;
  const limitRaw = req.query.limit;
  const page = Math.max(1, Number(pageRaw || 1) || 1);
  const limit = Math.min(200, Math.max(1, Number(limitRaw || 50) || 50));
  const offset = (page - 1) * limit;
  return { page, limit, offset };
}

async function listActivations(req, res) {
  try {
    const { page, limit, offset } = parsePagination(req);
    const license_id = req.query.license_id || undefined;
    const estado = req.query.estado ? String(req.query.estado).toUpperCase() : undefined;

    if (estado) {
      const allowed = new Set(['ACTIVA', 'REVOCADA']);
      if (!allowed.has(estado)) {
        return res.status(400).json({ ok: false, message: "estado inválido. Use: ACTIVA|REVOCADA" });
      }
    }

    const { total, activations } = await activationsModel.listActivations({
      limit,
      offset,
      license_id,
      estado
    });

    return res.json({ ok: true, page, limit, total, activations });
  } catch (error) {
    console.error('admin listActivations error:', error);
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
    return res.json({ ok: true, activation: updated });
  } catch (error) {
    console.error('admin revokeActivation error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno del servidor' });
  }
}

module.exports = {
  listActivations,
  revokeActivation
};
