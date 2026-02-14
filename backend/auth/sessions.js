const crypto = require('crypto');
const jwt = require('jsonwebtoken');

// Legacy: almacén en memoria (simple). Puede fallar en producción si hay
// múltiples instancias o reinicios. Se mantiene sólo para compatibilidad.
const activeSessions = Object.create(null);

let _warnedInsecureSecret = false;

function getJwtSecret() {
  const secret =
    process.env.ADMIN_SESSION_JWT_SECRET ||
    process.env.JWT_SECRET ||
    process.env.ADMIN_PASSWORD ||
    '';

  if (!secret || !String(secret).trim()) {
    if (!_warnedInsecureSecret) {
      _warnedInsecureSecret = true;
      // No romper el servidor por compatibilidad, pero advertir.
      console.warn(
        '[sessions] WARNING: Missing ADMIN_SESSION_JWT_SECRET/JWT_SECRET. Falling back to an insecure dev secret.'
      );
    }
    return 'dev-insecure-admin-session-secret';
  }

  // Si se usa password como secret, al menos evitar espacios.
  return String(secret).trim();
}

function createJwtSession(username) {
  const secret = getJwtSecret();
  return jwt.sign(
    {
      typ: 'admin',
      sub: String(username || '').trim() || 'admin'
    },
    secret,
    {
      algorithm: 'HS256',
      expiresIn: '24h',
      issuer: 'fulltechpos',
      audience: 'admin'
    }
  );
}

function createLegacySession(username) {
  const sessionId = crypto.randomBytes(24).toString('hex');
  activeSessions[sessionId] = {
    username,
    loginTime: new Date(),
    expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 horas
  };
  return sessionId;
}

function createSession(username) {
  // Default: JWT stateless sessions (stable across restarts / multiple instances)
  // Backwards compatible: legacy in-memory sessions kept for old tokens.
  return createJwtSession(username);
}

function looksLikeJwt(token) {
  const t = String(token || '').trim();
  // Rough check: header.payload.signature
  return t.split('.').length === 3;
}

function verifySessionId(sessionId) {
  const sid = String(sessionId || '').trim();
  if (!sid) {
    return { ok: false, status: 401, message: 'Sesión no válida o expirada' };
  }

  // 1) JWT sessions (preferred)
  if (looksLikeJwt(sid)) {
    try {
      const decoded = jwt.verify(sid, getJwtSecret(), {
        algorithms: ['HS256'],
        issuer: 'fulltechpos',
        audience: 'admin'
      });
      const username = (decoded && (decoded.sub || decoded.username))
        ? String(decoded.sub || decoded.username)
        : 'Admin';
      return {
        ok: true,
        sessionId: sid,
        session: {
          username,
          jwt: true,
          expiresAt: decoded && decoded.exp ? new Date(decoded.exp * 1000) : null
        }
      };
    } catch (_) {
      return { ok: false, status: 401, message: 'Sesión no válida o expirada' };
    }
  }

  // 2) Legacy in-memory session ids
  if (!activeSessions[sid]) {
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
  // JWT sessions are stateless; logout is handled client-side.
  if (!sid) return;
  if (activeSessions[sid]) delete activeSessions[sid];
}

module.exports = {
  activeSessions,
  createSession,
  verifySessionId,
  verifySessionMiddleware,
  destroySession
};
