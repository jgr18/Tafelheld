// Tafelheld service worker: zorgt dat de app installeerbaar is en ook start zonder internet.
// Altijd eerst vers van het netwerk halen (zo krijg je updates meteen), anders de bewaarde versie.
const CACHE = 'tafelheld-v2';
const SHELL = ['./', './index.html', './config.js', './manifest.json', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL))); self.skipWaiting(); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.hostname.endsWith('supabase.co') || url.pathname.includes('/auth/') || url.pathname.includes('/rest/')) return; // oefengegevens nooit cachen
  e.respondWith(
    fetch(e.request, { cache: 'no-store' }).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r; })
      .catch(() => caches.match(e.request, { ignoreSearch: true }))
  );
});
