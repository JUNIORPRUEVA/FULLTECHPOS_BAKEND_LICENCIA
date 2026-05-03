const auditLogsModel = require('../models/auditLogsModel');

function pickIp(req) {
  const forwarded = String(req?.headers?.['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || req?.ip || req?.socket?.remoteAddress || null;
}

function requestContext(req) {
  return {
    actor_user_id: null,
    actor_type: req?.sessionId ? 'admin_session' : 'system',
    ip_address: pickIp(req),
    user_agent: req?.headers?.['user-agent'] || null
  };
}

async function log(entry, options = {}) {
  const reqContext = options.req ? requestContext(options.req) : {};
  return auditLogsModel.create({
    ...reqContext,
    ...entry,
    before_data: entry.before_data || {},
    after_data: entry.after_data || {}
  }, options);
}

module.exports = {
  requestContext,
  log
};