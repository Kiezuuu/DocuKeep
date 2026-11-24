const CACHE_PREFIX = "docukeep-shell-";
const CACHE_NAME = "docukeep-shell-v7";
const APP_SHELL = [
  "./",
  "./index.html",
  "./offline.html",
  "./manifest.webmanifest",
  "./Logo.png",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./assets/docukeep-workspace-illustration.svg",
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"
];

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    for (const resource of APP_SHELL) {
      try {
        const response = await fetch(resource, { cache: "reload" });
        if (response.ok) await cache.put(resource, response);
      } catch (error) {
        console.warn("DocuKeep shell resource not cached:", resource, error);
      }
    }
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  // Authenticated API, database and private Storage responses must never enter Cache Storage.
  if (url.hostname.endsWith(".supabase.co")) return;

  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        if (response.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put("./index.html", response.clone());
        }
        return response;
      } catch (error) {
        return (await caches.match("./index.html")) ||
          (await caches.match("./offline.html")) ||
          new Response("DocuKeep is not available offline yet. Open it once while connected to the internet.", {
            status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" }
          });
      }
    })());
    return;
  }

  if (url.origin === self.location.origin || url.hostname === "cdn.jsdelivr.net") {
    const networkPromise = fetch(request).then(async response => {
      if (response.ok && response.type !== "opaque") {
        const cache = await caches.open(CACHE_NAME);
        await cache.put(request, response.clone());
      }
      return response;
    });
    // Extend the worker lifetime for the background cache refresh.
    event.waitUntil(networkPromise.catch(() => {}));
    event.respondWith((async () => {
      const cached = await caches.match(request);
      if (cached) return cached;
      try { return await networkPromise; }
      catch (error) {
        return new Response("This resource is unavailable offline.", {
          status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" }
        });
      }
    })());
  }
});

// Background Sync cannot upload private files by itself because the user's authenticated
// Supabase session belongs to the page. Ask an open DocuKeep page to process its IndexedDB queue.
self.addEventListener("sync", event => {
  if (event.tag === "docukeep-upload-sync") {
    event.waitUntil((async () => {
      const clientsList = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      for (const client of clientsList) client.postMessage({ type: "DOCUKEEP_SYNC_REQUEST" });
    })());
  }
});

self.addEventListener("message", event => {
  if (event.data?.type === "SKIP_WAITING") self.skipWaiting();
});
