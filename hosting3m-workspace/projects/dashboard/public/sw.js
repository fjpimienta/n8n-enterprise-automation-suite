// Minimalist service worker to satisfy Android Chromium PWA criteria
self.addEventListener('fetch', (event) => {
  // Acts as a passthrough stream without caching overhead
});