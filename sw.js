/* Note Cards service worker: the app opens from the cache with no connection,
   and a fresh copy is fetched in the background for next launch.
   Bump VERSION whenever any app file changes. Only caches named shed-deck-*
   are ever cleared, so other apps on the same site keep theirs. */
const PREFIX = "shed-deck-";
const VERSION = PREFIX + "v2.3.0";
const SHELL = ["./", "./index.html", "./manifest.webmanifest", "./icon.svg", "./icon-192.png", "./icon-512.png", "./icon-maskable-512.png", "./apple-touch-icon.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(VERSION).then((cache) => cache.addAll(SHELL)));
  self.skipWaiting();
});
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith(PREFIX) && k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});
function refresh(request, cacheKey) {
  return fetch(request).then((response) => {
    if (response && response.ok) {
      const copy = response.clone();
      caches.open(VERSION).then((cache) => cache.put(cacheKey || request, copy));
    }
    return response;
  });
}
self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (request.mode === "navigate") {
    event.respondWith(caches.open(VERSION).then((c) => c.match("./index.html")).then((cached) => {
      const network = refresh(request, "./index.html").catch(() => cached);
      return cached || network;
    }));
    return;
  }
  event.respondWith(caches.open(VERSION).then((c) => c.match(request, { ignoreSearch: true })).then((cached) => {
    const network = refresh(request).catch(() => cached);
    return cached || network;
  }));
});
