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

UPLOAD QUEUE CORRECTIONS (25 NOV 2026)
- Existing IndexedDB queue is upgraded in place (database version 3); the pendingUploads store and existing queued file blobs are retained.
- Queue jobs are scoped to the authenticated profile UUID and are processed serially in creation order. A different account's jobs are never selected for upload.
- Reconnection, focus, visibility return, and successful sign-in trigger synchronization. Temporary failures use bounded exponential retry intervals; permanent permission/quota/validation failures remain visible for manual review and are not automatically retried.
- Each queued file now displays real XMLHttpRequest byte progress, file size, and state. Pause aborts the current standard Storage POST and retains the local file; Resume starts that POST again. Supabase's standard single-request upload endpoint is not resumable, so byte progress cannot continue from the prior offset. A TUS/resumable upload endpoint would be required to resume from the exact byte offset.
- Cancel removes only the selected queue item and attempts to remove that item's exact Storage path if no document row exists. It never deletes a completed document row.
- Successful files briefly show Completed; the IndexedDB record no longer retains the file blob and is removed after the confirmation display. Stale Completed markers are cleaned up after one day.
- If Storage succeeds but the document metadata insert fails, the client checks for the document row and attempts to remove the exact orphaned Storage object. The original error remains in the developer console; the user sees a safe, actionable message.
- Button SVG styling now inherits the button's foreground color. Sidebar icon hover styling uses background-color rather than the background shorthand so the existing icon background-image is not cleared.

DATABASE P0001 STATUS
No database schema, trigger, function, quota rule, or RLS policy was changed in this pass. The ZIP does not include a live Supabase database snapshot or the actual Postgres error detail, so selecting a trigger to alter would be guesswork. Run docukeep_upload_diagnostics.sql in Supabase SQL Editor and inspect the matching failed INSERT in Supabase Dashboard > Logs > Postgres. The bundled migrations show at least these possible P0001 sources: enforce_docukeep_storage_quota(), enforce_docukeep_premium_features(), and docukeep_validate_document_folder_owner(). The actual exception message and trigger context are required to identify the one being raised in your project. Do not disable any of these guards or loosen RLS as a workaround.

TEST SCOPE
Static JavaScript syntax, HTML parsing, duplicate IDs, queue-state wiring, and ZIP integrity are checked locally. Live offline/online transitions, browser-close persistence, actual student/teacher/staff credentials, Supabase Storage cleanup, database trigger behavior, and hover rendering in a real browser still require testing against your deployed Supabase project and browsers. No live account or database was available in this workspace.
