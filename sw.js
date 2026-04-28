/* eslint-disable no-restricted-globals */

const CACHE_VERSION = 'v22';
const STATIC_CACHE = `fulltech-pos-static-${CACHE_VERSION}`;

const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/home.html',
  '/fullpos.html',
  '/products.html',
  '/product.html',
  '/offline.html',
  '/manifest.webmanifest',
  '/assets/css/styles.css',
  '/assets/css/jr.css',
  '/assets/css/admin-compact-bar.css',
  '/assets/css/jr-admin.css',
  '/assets/js/adminCompactBar.js',
  '/assets/js/pwa.js',
  '/assets/js/storePublic.js',
  '/assets/img/logo/logoprincipal.png',
  '/assets/img/pwa/icon-180.png',
  '/assets/img/pwa/icon-192.png',
  '/assets/img/pwa/icon-512.png',
  '/assets/img/pwa/icon-maskable-192.png',
  '/assets/img/pwa/icon-maskable-512.png'
];

function isSameOriginAsset(requestUrl) {
  try {
    const url = new URL(requestUrl);
    return url.origin === self.location.origin;
  } catch (_) {
    return false;
  }
}

function isFreshAsset(requestUrl) {
  try {
    const url = new URL(requestUrl);
    if (url.origin !== self.location.origin) return false;
    return /\.(?:css|js|html|webmanifest|png|svg|jpg|jpeg|webp)$/i.test(url.pathname) ||
      url.pathname === '/' ||
      url.pathname === '/home.html' ||
      url.pathname === '/fullpos.html' ||
      url.pathname === '/products.html' ||
      url.pathname === '/product.html';
  } catch (_) {
    return false;
  }
}

async function networkFirst(request, fallbackUrl) {
  try {
    const response = await fetch(request);
    if (request.method === 'GET' && response && response.ok && isSameOriginAsset(request.url)) {
      const cache = await caches.open(STATIC_CACHE);
      cache.put(request, response.clone()).catch(() => undefined);
    }
    return response;
  } catch (_) {
    const cached = await caches.match(request);
    if (cached) return cached;
    if (fallbackUrl) {
      const fallback = await caches.match(fallbackUrl);
      if (fallback) return fallback;
    }
    throw _;
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) => cache.addAll(PRECACHE_URLS)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith('fulltech-pos-static-') && key !== STATIC_CACHE)
          .map((key) => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Never cache API requests (avoids stale admin data like license-config).
  try {
    const url = new URL(request.url);
    if (url.origin === self.location.origin && url.pathname.startsWith('/api/')) {
      event.respondWith(fetch(request));
      return;
    }
  } catch (_) {
    // ignore URL parse errors and continue
  }

  // Navigation: network-first, fallback to cache, then offline page.
  if (request.mode === 'navigate') {
    event.respondWith(
      networkFirst(request, '/offline.html').catch(async () => {
        const indexCached = await caches.match('/index.html');
        return indexCached || caches.match('/offline.html');
      })
    );
    return;
  }

  // Admin assets/pages: network-first to avoid stale session/auth JS.
  try {
    const url = new URL(request.url);
    const isSameOrigin = url.origin === self.location.origin;
    const isAdminPath = url.pathname.startsWith('/admin/');
    const isAdminAsset = url.pathname.startsWith('/assets/js/admin') ||
      url.pathname.startsWith('/assets/css/jr-admin');
    if (isSameOrigin && (isAdminPath || isAdminAsset)) {
      event.respondWith(
        fetch(request).catch(async () => {
          const cached = await caches.match(request);
          return cached || fetch(request);
        })
      );
      return;
    }
  } catch (_) {
    // ignore
  }

  // Critical branded assets: network-first to avoid stale UI after deploys.
  if (request.method === 'GET' && isFreshAsset(request.url)) {
    event.respondWith(
      networkFirst(request).catch(async () => {
        const cached = await caches.match(request);
        return cached || fetch(request);
      })
    );
    return;
  }

  // Other static assets: cache-first.
  event.respondWith(
    caches.match(request).then((cached) =>
      cached ||
      fetch(request)
        .then((response) => {
          // Only cache successful, same-origin GETs.
          try {
            const url = new URL(request.url);
            if (request.method === 'GET' && url.origin === self.location.origin && response.ok) {
              const copy = response.clone();
              caches.open(STATIC_CACHE).then((cache) => cache.put(request, copy)).catch(() => undefined);
            }
          } catch (_) {
            // ignore
          }
          return response;
        })
        .catch(() => cached)
    )
  );
});
