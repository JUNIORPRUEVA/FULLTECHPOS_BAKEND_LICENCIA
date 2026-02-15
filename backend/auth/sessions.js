const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { pool } = require('../db/pool');

// Cache en memoria (optimización). La fuente de verdad es Postgres.
const activeSessions = Object.create(null);

const AUTH_DEBUG = String(process.env.AUTH_DEBUG || '').trim() === '1';

function parseTtlMs() {
  const daysRaw = String(process.env.ADMIN_SESSION_TTL_DAYS || '').trim();
  const msRaw = String(process.env.ADMIN_SESSION_TTL_MS || '').trim();

  if (msRaw && Number.isFinite(Number(msRaw))) {
    return Math.max(60_000, Number(msRaw));
  }

  if (daysRaw && Number.isFinite(Number(daysRaw))) {
    return Math.max(1, Number(daysRaw)) * 24 * 60 * 60 * 1000;
  }

  // Default: 30 días (admin sessions)
  return 30 * 24 * 60 * 60 * 1000;
}

const SESSION_TTL_MS = parseTtlMs();
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

async function createSessionAsync(username) {
  const sessionId = crypto.randomBytes(24).toString('hex');
  const now = Date.now();
  const expiresAt = new Date(now + SESSION_TTL_MS);

  // Pre-fill cache for same-instance calls.
  activeSessions[sessionId] = {
    username,
    loginTime: new Date(now),
    expiresAt
  };

  await ensureAdminSessionsTable();
  await pool.query(
    `INSERT INTO admin_sessions (session_id, username, expires_at)
     VALUES ($1, $2, $3)
     ON CONFLICT (session_id) DO UPDATE
       SET username = EXCLUDED.username,
           expires_at = EXCLUDED.expires_at`,
    [sessionId, String(username || '').trim() || 'Admin', expiresAt]
  );

  if (AUTH_DEBUG) {
    console.log('[sessions] created session', {
      sidPrefix: sessionId.slice(0, 8),
      ttlMs: SESSION_TTL_MS
    });
  }

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
  if (AUTH_DEBUG) {
    const sid = String(sessionId || '');
    console.log('[sessions] verify', {
      method: req.method,
      path: req.originalUrl || req.url,
      hasSid: Boolean(sid),
      sidPrefix: sid ? sid.slice(0, 8) : null,
      origin: req.headers.origin || null,
      host: req.headers.host || null,
      xfProto: req.headers['x-forwarded-proto'] || null,
      proto: req.protocol || null
    });
  }
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

      // Sliding expiration: extend on successful activity.
      const newExpiresAt = new Date(Date.now() + SESSION_TTL_MS);
      try {
        await pool.query(
          'UPDATE admin_sessions SET last_seen_at = NOW(), expires_at = $2 WHERE session_id = $1',
          [sid, newExpiresAt]
        );
      } catch (_) {}

      // Update cache + last_seen
      activeSessions[sid] = {
        username: row.username,
        loginTime: new Date(),
        expiresAt: newExpiresAt
      };

      if (AUTH_DEBUG) {
        const now = Date.now();
        const expMs = newExpiresAt.getTime();
        console.log('[sessions] ok', {
          sidPrefix: sid.slice(0, 8),
          expiresInSec: Math.round((expMs - now) / 1000)
        });
      }

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
  createSessionAsync,
  verifySessionId,
  verifySessionMiddleware,
  destroySession
};
