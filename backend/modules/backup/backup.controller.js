const service = require('./backup.service');

function sendError(res, err) {
  const status = err.status || 500;
  res.status(status).json({
    success: false,
    code: err.code || 'ERROR',
    message: err.message || 'Error'
  });
}

async function push(req, res) {
  try {
    const ctx = await service.resolveContextFromHeaders(req);
    const saved = await service.pushBackup({
      companyId: ctx.companyId,
      deviceId: ctx.deviceId,
      backupJson: req.body
    });

    return res.json({
      success: true,
      backup: saved
    });
  } catch (err) {
    return sendError(res, err);
  }
}

async function pull(req, res) {
  try {
    const ctx = await service.resolveContextFromHeaders(req);
    const latest = await service.pullLatestBackup({
      companyId: ctx.companyId,
      deviceId: ctx.deviceId
    });

    // Si el dispositivo es nuevo (reinstalación) puede no tener backups aún.
    // Permitir restaurar el último backup de la empresa.
    const fallback = latest ? null : await service.pullLatestBackupForCompany({ companyId: ctx.companyId });

    const row = latest || fallback;

    if (!row) {
      return res.status(404).json({
        success: false,
        code: 'NOT_FOUND',
        message: 'No hay backups'
      });
    }

    return res.json({
      success: true,
      backup: {
        id: row.id,
        device_id: row.device_id,
        created_at: row.created_at,
        backup_json: row.backup_json
      }
    });
  } catch (err) {
    return sendError(res, err);
  }
}

async function history(req, res) {
  try {
    const ctx = await service.resolveContextFromHeaders(req);
    const limit = req.query.limit;
    const rows = await service.listBackupHistory({
      companyId: ctx.companyId,
      deviceId: ctx.deviceId,
      limit
    });

    return res.json({
      success: true,
      backups: rows
    });
  } catch (err) {
    return sendError(res, err);
  }
}

module.exports = { push, pull, history };
