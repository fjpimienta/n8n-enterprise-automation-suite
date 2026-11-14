// Transition worker (Refs #1087). The hand-written PWA worker that used the cache
// 'agroerp-pwa-v2' is gone; the app now registers Angular's /ngsw-worker.js at the same scope
// ("/"), which replaces this registration. This file stays at /sw.js ONLY so that browsers
// that already have the old worker installed pick up this version on their next update check,
// remove the legacy cache and stop serving cached responses.
// It deliberately has no fetch handler and does not unregister itself: unregistering would leave
// the app without a worker until ngsw registers. Do not delete it until old installs are gone.
const LEGACY_CACHES = ['agroerp-pwa-v2'];

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    Promise.all(LEGACY_CACHES.map((name) => caches.delete(name))).then(() => self.clients.claim())
  );
});
