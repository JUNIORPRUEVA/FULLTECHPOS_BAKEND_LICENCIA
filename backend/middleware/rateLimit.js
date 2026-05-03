/**
 * rateLimit.js — simple in-memory rate limiter (no external dependencies).
 *
 * Used to throttle public license endpoints that do DB look-ups.
 * For multi-process/multi-node deployments, replace with Redis-backed limiter.
 *
 * Usage:
 *   const { rateLimit } = require('./rateLimit');
 *   app.use('/api/licenses', rateLimit({ windowMs: 60_000, max: 60 }));
 */

'use strict';

/**
 * Sliding window in-memory store.
 * Keys are IP addresses. Clean-up happens lazily on each request.
 */
function createStore(windowMs) {
  const buckets = Object.create(null);

  function cleanup(now) {
    const cutoff = now - windowMs;
    for (const key of Object.keys(buckets)) {
      // Keep only timestamps inside the window
      buckets[key] = buckets[key].filter((t) => t > cutoff);
      if (buckets[key].length === 0) delete buckets[key];
    }
  }

  let lastCleanup = Date.now();

  return {
    increment(key) {
      const now = Date.now();
      // Periodic cleanup every 30 s to avoid unbounded memory growth.
      if (now - lastCleanup > 30_000) {
        cleanup(now);
        lastCleanup = now;
      }
      if (!buckets[key]) buckets[key] = [];
      buckets[key].push(now);
      return buckets[key].filter((t) => t > now - windowMs).length;
    }
  };
}

/**
 * @param {object} opts
 * @param {number} opts.windowMs  - Time window in milliseconds (default 60_000)
 * @param {number} opts.max       - Max requests per window per IP (default 60)
 * @param {string} [opts.message] - Error message
 */
function rateLimit({ windowMs = 60_000, max = 60, message = 'Demasiadas peticiones. Intente más tarde.' } = {}) {
  const store = createStore(windowMs);

  return function rateLimitMiddleware(req, res, next) {
    const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
    const ip = forwarded || req.ip || req.socket?.remoteAddress || 'unknown';
    const count = store.increment(ip);

    if (count > max) {
      res.set('Retry-After', Math.ceil(windowMs / 1000));
      return res.status(429).json({ ok: false, message });
    }

    next();
  };
}

module.exports = { rateLimit };
