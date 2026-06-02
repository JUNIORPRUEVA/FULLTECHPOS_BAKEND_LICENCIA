// Auth simple: valida la sesión creada por /api/login vía header x-session-id.
// En producción: reemplazar por auth real (JWT/DB/Redis/roles).
const sessions = require('../auth/sessions');

const AUTH_DEBUG = String(process.env.AUTH_DEBUG || '').trim() === '1';

module.exports = function isAdmin(req, res, next) {
  if (AUTH_DEBUG) {
    const sid = String(req.headers['x-session-id'] || req.query.sessionId || '');
    console.log('[isAdmin]', {
      method: req.method,
      path: req.originalUrl || req.url,
      hasSessionId: Boolean(sid),
      sidPrefix: sid ? sid.slice(0, 8) : null,
      hasAuthorization: Boolean(req.headers.authorization),
    });
  }
  return sessions.verifySessionMiddleware(req, res, next);
};
