// Auth simple: valida la sesión creada por /api/login vía header x-session-id.
// En producción: reemplazar por auth real (JWT/DB/Redis/roles).
const sessions = require('../auth/sessions');

module.exports = function isAdmin(req, res, next) {
  return sessions.verifySessionMiddleware(req, res, next);
};
