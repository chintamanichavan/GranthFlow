// Offline: the shell and the engine are cached on install, so the app opens with no network.
// The books themselves are never cached here — they live in IndexedDB, put there by the page.
//
// VERSION is the cache's name. Raise it whenever the shell or the engine changes; the old cache
// is then dropped on activate, which is what stops a stale page from loading a new engine.
const VERSION = "granthflow-v1";

const SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./app/style.css",
  "./app/main.js",
  "./app/reader.js",
  "./app/store.js",
  "./app/engine.js",
  "./app/document.js",
  "./app/cover.js",
  "./vendor/anyfile.mjs",
  "./vendor/anyfile.wasm",
  "./icons/icon_128.png",
  "./icons/icon_256.png",
  "./icons/icon_512.png",
  "./icons/icon_1024.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(VERSION).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names.filter((name) => name !== VERSION).map((name) => caches.delete(name))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Cache first: the shell and the engine do not change until a new VERSION replaces them, and
  // reading must not wait on the network to find that out.
  event.respondWith(
    caches.match(request, { ignoreSearch: true }).then((hit) => {
      if (hit) return hit;
      return fetch(request)
        .then((response) => {
          if (response.ok && response.type === "basic") {
            const copy = response.clone();
            caches.open(VERSION).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => (request.mode === "navigate" ? caches.match("./index.html") : Response.error()));
    }),
  );
});
