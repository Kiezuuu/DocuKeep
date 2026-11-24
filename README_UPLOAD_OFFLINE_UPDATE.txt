DOCUKEEP UPLOAD + OFFLINE/PWA UPDATE

Files changed:
- index.html: upload validation, online/server reachability checks, persistent upload queue, session ownership checks, idempotent document creation, queue status display, and Background Sync registration.
- sw.js: versioned app-shell cache, safe offline navigation fallback, cache refresh, and Background Sync notification to an authenticated open page.
- manifest.webmanifest: DocuKeep install metadata and app icons.
- offline.html: custom offline fallback page.
- docukeep_upload_permissions_migration.sql: additive RLS policies for approved students, teachers, and staff to insert their own document metadata and upload into their own private Storage folder.

IMPORTANT DEPLOYMENT STEPS
1. Back up your Supabase project.
2. Run docukeep_upload_permissions_migration.sql in Supabase SQL Editor.
3. Deploy the updated index.html, sw.js, manifest.webmanifest, offline.html, Logo.png, icons/, and assets/ together to the existing GitHub Pages repository root.
4. Keep the existing docukeep-files bucket PRIVATE and retain its current 25 MB per-file limit and quota guard.
5. Open DocuKeep online once, sign in, and allow the new service worker to install. Then test offline behavior.
6. Sign in again after reconnecting if the authentication session expired. Queued file blobs remain in IndexedDB and are not discarded on session expiry.

IMPLEMENTATION NOTES / LIMITATIONS
- IndexedDB database name remains docukeep-offline-v1 and is upgraded in place to preserve existing queued files.
- Direct uploads show byte-level progress using the authenticated Supabase Storage upload endpoint.
- The browser's online event is not treated as proof of server availability; the app checks the Supabase Auth health endpoint before syncing.
- The private Supabase API and private file responses are never cached by the service worker.
- Background Sync asks an open DocuKeep page to upload because the page owns the authenticated Supabase session. Browsers without Background Sync use online, focus, and visibility events.
- Previously cached app-shell pages can open offline, but authentication, database reads, signed URLs, remote previews, and server-side actions still require internet.
- The browser must have opened DocuKeep online at least once to cache the app shell. Service workers require HTTPS (GitHub Pages provides HTTPS).
- Browser storage quota and the device's available storage limit how many offline files can be queued.
- A successful upload is only removed from IndexedDB after the document row is confirmed on Supabase.
- This package cannot test your live Supabase RLS, bucket configuration, or deployed GitHub Pages environment. Run the test checklist with separate student, teacher, and staff accounts after applying the migration.
