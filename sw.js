
const CACHE_NAME = "docukeep-shell-v2";

const SHELL_FILES = [
  "./",
  "./index.html",
  "./manifest.webmanifest"
];

const CDN_FILES = [
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"
];

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);

    for (const file of SHELL_FILES) {
      try {
        await cache.add(file);
      } catch (error) {
        console.warn("Could not cache:", file, error);
      }
    }

    for (const file of CDN_FILES) {
      try {
        const response = await fetch(file);
        if (response.ok) {
          await cache.put(file, response);
        }
      } catch (error) {
        console.warn("Could not cache Supabase SDK:", error);
      }
    }

    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();

    await Promise.all(
      keys
        .filter(key => key.startsWith("docukeep-shell-") && key !== CACHE_NAME)
        .map(key => caches.delete(key))
    );

    await self.clients.claim();
  })());
});

self.addEventListener("fetch", event => {
  const request = event.request;

  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // Never cache private Supabase database, authentication,
  // or storage requests.
  if (url.hostname.endsWith(".supabase.co")) return;

  // Supabase JavaScript SDK: network first, cached fallback.
  if (
    url.hostname === "cdn.jsdelivr.net" &&
    url.pathname.includes("/npm/@supabase/supabase-js")
  ) {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);

        if (response.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put(request, response.clone());
        }

        return response;
      } catch (error) {
        const cached = await caches.match(request);

        if (cached) return cached;

        return new Response(
          "Supabase SDK is unavailable offline. Open DocuKeep while connected to the internet first.",
          {
            status: 503,
            headers: { "Content-Type": "text/plain" }
          }
        );
      }
    })());

    return;
  }

  // App navigation: network first, offline app-shell fallback.
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
        return (
          await caches.match("./index.html") ||
          await caches.match("./") ||
          new Response("DocuKeep is not available offline yet.", {
            status: 503,
            headers: { "Content-Type": "text/plain" }
          })
        );
      }
    })());

    return;
  }

  // Cache-first for same-origin static app files only.
  if (url.origin === self.location.origin) {
    event.respondWith((async () => {
      const cached = await caches.match(request);

      if (cached) return cached;

      try {
        const response = await fetch(request);

        if (response.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put(request, response.clone());
        }

        return response;
      } catch (error) {
        return new Response("This resource is unavailable offline.", {
          status: 503,
          headers: { "Content-Type": "text/plain" }
        });
      }
    })());
  }
});
