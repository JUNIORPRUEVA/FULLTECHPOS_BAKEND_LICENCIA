const crypto = require('crypto');

// Almacén en memoria (simple). En producción: Redis/DB/JWT.
const activeSessions = Object.create(null);

function createSession(username) {
  const sessionId = crypto.randomBytes(24).toString('hex');
  activeSessions[sessionId] = {
    username,
    loginTime: new Date(),
    expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 horas
  };
  return sessionId;
}

function verifySessionId(sessionId) {
  const sid = String(sessionId || '').trim();
  if (!sid || !activeSessions[sid]) {
    return { ok: false, status: 401, message: 'Sesión no válida o expirada' };
  }

  const session = activeSessions[sid];
  if (new Date() > new Date(session.expiresAt)) {
    delete activeSessions[sid];
    return { ok: false, status: 401, message: 'Sesión expirada' };
  }

  return { ok: true, sessionId: sid, session };
}

function verifySessionMiddleware(req, res, next) {
  const sessionId = req.headers['x-session-id'] || req.query.sessionId;
  const result = verifySessionId(sessionId);
  if (!result.ok) {
    return res.status(result.status).json({ success: false, message: result.message });
  }

  req.sessionId = result.sessionId;
  req.adminUser = result.session?.username;
  next();
}

function destroySession(sessionId) {
  const sid = String(sessionId || '').trim();
  if (sid && activeSessions[sid]) delete activeSessions[sid];
}

module.exports = {
  activeSessions,
  createSession,
  verifySessionId,
  verifySessionMiddleware,
  destroySession
};
