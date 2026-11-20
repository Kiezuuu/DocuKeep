const CACHE_NAME = "docukeep-shell-v5";
const SHELL_FILES = ["./", "./index.html", "./manifest.webmanifest"];
const CDN_FILES = ["https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"];

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    for (const file of SHELL_FILES) { try { await cache.add(file); } catch (error) { console.warn("Could not cache:", file, error); } }
    for (const file of CDN_FILES) { try { const response = await fetch(file); if (response.ok) await cache.put(file, response); } catch (error) { console.warn("Could not cache Supabase SDK:", error); } }
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith("docukeep-shell-") && key !== CACHE_NAME).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("push", event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch { payload = { body: event.data?.text() || "You have a new DocuKeep update." }; }
  const title = payload.title || "DocuKeep notification";
  const options = {
    body: payload.body || payload.message || "You have a new update.",
    icon: "./icons/icon-192.png",
    badge: "./icons/icon-192.png",
    tag: payload.tag || payload.notification_id || "docukeep-update",
    renotify: false,
    data: { url: payload.url || "./", notification_id: payload.notification_id || null }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || "./", self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of windows) {
      if (client.url.startsWith(self.location.origin) && "focus" in client) { await client.focus(); if ("navigate" in client) await client.navigate(target); return; }
    }
    if (self.clients.openWindow) await self.clients.openWindow(target);
  })());
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.hostname.endsWith(".supabase.co")) return;
  if (url.hostname === "cdn.jsdelivr.net" && url.pathname.includes("/npm/@supabase/supabase-js")) {
    event.respondWith((async () => { try { const response = await fetch(request); if (response.ok) { const cache = await caches.open(CACHE_NAME); await cache.put(request, response.clone()); } return response; } catch { const cached = await caches.match(request); return cached || new Response("Supabase SDK is unavailable offline. Open DocuKeep while connected first.", { status: 503, headers: { "Content-Type": "text/plain" } }); } })()); return;
  }
  if (request.mode === "navigate") {
    event.respondWith((async () => { try { const response = await fetch(request); if (response.ok) { const cache = await caches.open(CACHE_NAME); await cache.put("./index.html", response.clone()); } return response; } catch { return await caches.match("./index.html") || await caches.match("./") || new Response("DocuKeep is not available offline yet.", { status: 503, headers: { "Content-Type": "text/plain" } }); } })()); return;
  }
  if (url.origin === self.location.origin) {
    event.respondWith((async () => { const cached = await caches.match(request); if (cached) return cached; try { const response = await fetch(request); if (response.ok) { const cache = await caches.open(CACHE_NAME); await cache.put(request, response.clone()); } return response; } catch { return new Response("This resource is unavailable offline.", { status: 503, headers: { "Content-Type": "text/plain" } }); } })());
  }
});
