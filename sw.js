// Service Worker: macht die App offline verfügbar.
// Bei jeder Änderung an index.html die Versionsnummer erhöhen.
const VERSION = "stundenbuch-v16";
const DATEIEN = ["./", "./index.html", "./manifest.json", "./icon-192.png", "./icon-512.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(DATEIEN)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(k => Promise.all(k.filter(n => n !== VERSION).map(n => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  // Datenbankaufrufe niemals aus dem Cache beantworten
  if (e.request.method !== "GET" || url.pathname.includes("/rest/v1/")) return;
  if (url.origin !== self.location.origin) return;

  e.respondWith(
    fetch(e.request)
      .then(a => {
        const kopie = a.clone();
        caches.open(VERSION).then(c => c.put(e.request, kopie));
        return a;
      })
      .catch(() => caches.match(e.request).then(t => t || caches.match("./index.html")))
  );
});
