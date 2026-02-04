/* eslint-disable no-restricted-globals */

const CACHE_VERSION = 'v14';
const STATIC_CACHE = `fulltech-pos-static-${CACHE_VERSION}`;

const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/home.html',
  '/products.html',
  '/product.html',
  '/offline.html',
  '/manifest.webmanifest',
  '/assets/css/styles.css',
  '/assets/css/jr.css',
  '/assets/css/jr-admin.css',
  '/assets/js/pwa.js',
  '/assets/js/storePublic.js',
  '/assets/img/pwa/icon-192.png',
  '/assets/img/pwa/icon-512.png',
  '/assets/img/pwa/icon-maskable-192.png',
  '/assets/img/pwa/icon-maskable-512.png'
];

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
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(STATIC_CACHE).then((cache) => cache.put('/index.html', copy)).catch(() => undefined);
          return response;
        })
        .catch(async () => {
          const cached = await caches.match(request);
          if (cached) return cached;
          const indexCached = await caches.match('/index.html');
          if (indexCached) return indexCached;
          return caches.match('/offline.html');
        })
    );
    return;
  }

  // Static assets: cache-first.
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
