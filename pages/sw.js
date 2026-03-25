const CACHE_VERSION = '1.0.1';
const SHELL_CACHE = `kbbi-shell-v${CACHE_VERSION}`;
const DB_CACHE = `kbbi_cache_vi_${CACHE_VERSION}`;

const KNOWN_CACHES = new Set([SHELL_CACHE, DB_CACHE]);

const SHELL_ASSETS = [
  './index.html',
  './style.css',
  './kbbi.js'
];

function createOfflineResponse() {
  return new Response('Layanan tidak tersedia — berkas offline tidak ditemukan', {
    status: 503,
    statusText: 'Service Unavailable',
    headers: { 'Content-Type': 'text/plain; charset=utf-8' }
  });
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then((cache) => cache.addAll(SHELL_ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) =>
      Promise.all(
        cacheNames
          .filter(name => !KNOWN_CACHES.has(name))
          .map(name => {
            console.log('[SW] Deleting old cache:', name);
            return caches.delete(name);
          })
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (request.method !== 'GET') return;
  if (url.origin !== location.origin) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;

      return fetch(request).then((response) => {
        if (!response || response.status !== 200 || response.type === 'error') {
          return response;
        }
        const clone = response.clone();
        event.waitUntil(
          caches.open(SHELL_CACHE)
            .then((cache) => cache.put(request, clone))
            .catch((err) => console.warn('[SW] Failed to cache runtime response:', request.url, err))
        );
        return response;
      }).catch(() => {
        if (request.mode === 'navigate') {
          return caches.match('./index.html').then((cachedIndex) => {
            if (cachedIndex) return cachedIndex;
            return createOfflineResponse();
          });
        }
        return createOfflineResponse();
      });
    })
  );
});