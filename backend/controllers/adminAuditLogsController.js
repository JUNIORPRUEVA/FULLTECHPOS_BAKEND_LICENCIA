const auditLogsModel = require('../models/auditLogsModel');

function asUuid(value) {
  const raw = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw)
    ? raw
    : null;
}

async function listAuditLogs(req, res) {
  try {
    const data = await auditLogsModel.list({
      company_id: asUuid(req.query.company_id),
      actor_user_id: asUuid(req.query.actor_user_id),
      target_type: req.query.target_type ? String(req.query.target_type).trim() : undefined,
      action: req.query.action ? String(req.query.action).trim() : undefined,
      date_from: req.query.date_from ? new Date(String(req.query.date_from)) : undefined,
      date_to: req.query.date_to ? new Date(String(req.query.date_to)) : undefined,
      limit: Math.min(200, Math.max(1, Number(req.query.limit) || 100)),
      offset: Math.max(0, Number(req.query.offset) || 0)
    });
    return res.json({ ok: true, ...data });
  } catch (error) {
    console.error('listAuditLogs error:', error);
    return res.status(500).json({ ok: false, message: 'Error interno' });
  }
}

module.exports = {
  listAuditLogs
};