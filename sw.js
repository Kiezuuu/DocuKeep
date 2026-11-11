const CACHE_NAME = 'docukeep-shell-v1';
const SHELL = ['./', './index.html', './manifest.webmanifest'];
self.addEventListener('install', event => { event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', event => {
  const req = event.request; const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;
  // Cache only the app shell/static same-origin assets; never cache authenticated API or private file responses.
  if (req.mode === 'navigate') { event.respondWith(fetch(req).then(res => { const copy = res.clone(); caches.open(CACHE_NAME).then(c => c.put('./index.html', copy)); return res; }).catch(() => caches.match('./index.html').then(r => r || caches.match('./')))); return; }
  if (['.css', '.js', '.png', '.svg', '.webmanifest'].some(ext => url.pathname.endsWith(ext))) {
    event.respondWith(caches.match(req).then(cached => cached || fetch(req).then(res => { if (res.ok) { const copy = res.clone(); caches.open(CACHE_NAME).then(c => c.put(req, copy)); } return res; })));
  }
});
