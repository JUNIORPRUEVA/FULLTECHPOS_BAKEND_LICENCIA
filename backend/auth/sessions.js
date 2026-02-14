const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { pool } = require('../db/pool');

// Cache en memoria (optimización). La fuente de verdad es Postgres.
const activeSessions = Object.create(null);

const SESSION_TTL_MS = 24 * 60 * 60 * 1000; // 24 horas
let _tableEnsured = false;

async function ensureAdminSessionsTable() {
  if (_tableEnsured) return;
  _tableEnsured = true;
  // No usamos migración aquí para mantener compatibilidad con installs ya en producción.
  await pool.query(
    `CREATE TABLE IF NOT EXISTS admin_sessions (
      session_id TEXT PRIMARY KEY,
      username TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL,
      last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )`
  );
}

function getJwtSecret() {
  const secret = process.env.ADMIN_SESSION_JWT_SECRET || process.env.JWT_SECRET || '';
  return String(secret || '').trim();
}

function looksLikeJwt(token) {
  const t = String(token || '').trim();
  // Rough check: header.payload.signature
  return t.split('.').length === 3;
}

function createSession(username) {
  // Default: sesiones persistentes por DB (robusto para reinicios y multi-instancia)
  const sessionId = crypto.randomBytes(24).toString('hex');
  const now = Date.now();
  activeSessions[sessionId] = {
    username,
    loginTime: new Date(now),
    expiresAt: new Date(now + SESSION_TTL_MS)
  };

  // Insert async best-effort (pero usualmente debe funcionar).
  ensureAdminSessionsTable()
    .then(() =>
      pool.query(
        `INSERT INTO admin_sessions (session_id, username, expires_at)
         VALUES ($1, $2, $3)
         ON CONFLICT (session_id) DO UPDATE SET username = EXCLUDED.username, expires_at = EXCLUDED.expires_at`,
        [sessionId, String(username || '').trim() || 'Admin', new Date(now + SESSION_TTL_MS)]
      )
    )
    .catch((e) => {
      console.error('[sessions] ensure/insert admin_sessions failed:', e.message || e);
    });

  return sessionId;
}

function verifySessionId(sessionId) {
  const sid = String(sessionId || '').trim();
  if (!sid) {
    return { ok: false, status: 401, message: 'Sesión no válida o expirada' };
  }

  // Optional: JWT sessions (only if enabled via secret).
  if (looksLikeJwt(sid)) {
    const secret = getJwtSecret();
    if (!secret) {
      return { ok: false, status: 401, message: 'Sesión no válida o expirada' };
    }
    try {
      const decoded = jwt.verify(sid, secret, {
        algorithms: ['HS256'],
        issuer: 'fulltechpos',
        audience: 'admin'
      });
      const username = decoded && (decoded.sub || decoded.username)
        ? String(decoded.sub || decoded.username)
        : 'Admin';
      return { ok: true, sessionId: sid, session: { username, jwt: true } };
    } catch (_) {
      return { ok: false, status: 401, message: 'Sesión no válida o expirada' };
    }
  }

  // 1) In-memory cache fast path
  const cached = activeSessions[sid];
  if (cached) {
    if (new Date() > new Date(cached.expiresAt)) {
      delete activeSessions[sid];
    } else {
      return { ok: true, sessionId: sid, session: cached };
    }
  }

  // 2) DB-backed lookup (sync-style response; caller middleware is sync)
  // We can't await here, so we return a special marker and let middleware handle async.
  return { ok: null, status: 0, message: 'DB_LOOKUP_REQUIRED', sessionId: sid };
}

function verifySessionMiddleware(req, res, next) {
  const sessionId = req.headers['x-session-id'] || req.query.sessionId;
  const result = verifySessionId(sessionId);

  // ok === true: pass
  if (result.ok === true) {
    req.sessionId = result.sessionId;
    req.adminUser = result.session?.username;
    return next();
  }

  // ok === false: fail
  if (result.ok === false) {
    return res.status(result.status).json({ success: false, message: result.message });
  }

  // ok === null: DB lookup required
  (async () => {
    try {
      await ensureAdminSessionsTable();
      const sid = result.sessionId;
      const dbRes = await pool.query(
        `SELECT session_id, username, expires_at
         FROM admin_sessions
         WHERE session_id = $1`,
        [sid]
      );
      const row = dbRes.rows[0] || null;
      if (!row) {
        return res.status(401).json({ success: false, message: 'Sesión no válida o expirada' });
      }

      const expiresAt = row.expires_at ? new Date(row.expires_at) : null;
      if (expiresAt && new Date() > expiresAt) {
        try {
          await pool.query('DELETE FROM admin_sessions WHERE session_id = $1', [sid]);
        } catch (_) {}
        return res.status(401).json({ success: false, message: 'Sesión expirada' });
      }

      // Update cache + last_seen
      activeSessions[sid] = {
        username: row.username,
        loginTime: new Date(),
        expiresAt: expiresAt || new Date(Date.now() + SESSION_TTL_MS)
      };
      try {
        await pool.query('UPDATE admin_sessions SET last_seen_at = NOW() WHERE session_id = $1', [sid]);
      } catch (_) {}

      req.sessionId = sid;
      req.adminUser = row.username;
      return next();
    } catch (e) {
      console.error('[sessions] verify middleware db error:', e.message || e);
      return res.status(500).json({ success: false, message: 'Error interno del servidor' });
    }
  })();
}

function destroySession(sessionId) {
  const sid = String(sessionId || '').trim();
  if (!sid) return;
  if (activeSessions[sid]) delete activeSessions[sid];
  // Best-effort remove from DB
  ensureAdminSessionsTable()
    .then(() => pool.query('DELETE FROM admin_sessions WHERE session_id = $1', [sid]))
    .catch(() => undefined);
}

module.exports = {
  activeSessions,
  createSession,
  verifySessionId,
  verifySessionMiddleware,
  destroySession
};
