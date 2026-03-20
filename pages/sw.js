const CACHE_VERSION = 'v0.0.1';
const SHELL_CACHE = `kbbi-shell-${CACHE_VERSION}`;

const SHELL_ASSETS = [
  './index.html',
  './style.css',
  './kbbi.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE).then((cache) =>
      Promise.allSettled(
        SHELL_ASSETS.map(asset =>
          cache.add(asset).catch(err => console.warn('[SW] Failed to cache:', asset, err))
        )
      )
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) =>
      Promise.all(
        cacheNames
          .filter(name => name !== SHELL_CACHE && !name.startsWith('kbbi_cache'))
          .map(name => caches.delete(name))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (request.method !== 'GET') return;
  if (url.origin !== location.origin) return;

  if (url.pathname.endsWith('.db')) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;

      return fetch(request).then((response) => {
        if (!response || response.status !== 200 || response.type === 'error') {
          return response;
        }
        const clone = response.clone();
        caches.open(SHELL_CACHE).then((cache) => cache.put(request, clone));
        return response;
      }).catch(() =>
        caches.match(request).then((cached) => {
          if (cached) return cached;
          return new Response('Offline — halaman tidak tersedia', {
            status: 503,
            statusText: 'Service Unavailable',
            headers: { 'Content-Type': 'text/plain; charset=utf-8' }
          });
        })
      );
    })
  );
});