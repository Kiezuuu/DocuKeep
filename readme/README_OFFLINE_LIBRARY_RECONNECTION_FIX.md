# DocuKeep Offline Library and Automatic Reconnection Fix

## Scope

This update targets the existing DocuKeep application in place. It keeps the existing HTML/CSS interface, Supabase client and authentication flow, database schema, Storage policies, upload queue, IndexedDB database name/object stores, device authorization format, and offline signature verification.

## Root cause addressed

The main `loadDocuments()` function returned immediately whenever `offlineMode` was active or `navigator.onLine` was false. That prevented the existing My Documents library from populating its shared `documents` array from IndexedDB. In addition, cache reconciliation deleted locally stored files on refresh, which conflicted with the requirement to preserve cached files. Offline preview also routed users to a download-only action rather than using the existing preview modal.

## Files changed

- `index.html`
  - `loadDocuments()` now reads the current account's encrypted IndexedDB cache when offline and passes it to the existing `renderDocuments()` and `renderDashboard()` functions.
  - The encrypted cache metadata now retains the full document row returned by the existing authorized Supabase query, including folder and additional metadata fields.
  - Refresh reconciliation no longer deletes cached file records.
  - Automatic cache hydration avoids replacing a cached copy when the server does not provide a hash to prove that the server copy is newer.
  - Offline previews use the existing preview modal for PDFs, images, and text-based files. Unsupported formats remain downloadable from the cache.
  - Connection handling now checks Supabase reachability, serializes reconnect attempts, responds to online/offline/focus/visibility events, and performs a guarded 30-second check while the app is active.
- `scripts/verify-offline-key.mjs`
  - The local verifier now compares against the exact public key required by the project request.

## IndexedDB caching

The existing database `docukeep-offline-v1` and its existing stores are retained. Document file bytes and metadata continue to be encrypted with the per-device AES-GCM data key and bound to the account/document IDs using authenticated additional data. No database reset or object-store deletion was introduced. Cache records are retained during refreshes and reconnection.

Automatic hydration still depends on the existing device authorization being provisioned and on the signed Storage download succeeding. A metadata row alone is not treated as a cached file; attempting to open a metadata-only record reports that its contents are unavailable offline.

## Reconnection and authentication

The reconnect flow checks the Supabase REST endpoint rather than trusting `navigator.onLine` alone, then checks the existing Supabase session and account identity. If a valid session is present, the existing profile validation path runs, pending uploads are synchronized through the existing queue, and the library is refreshed without reloading the page. If there is no Supabase session (the existing offline-only login deliberately does not create one), the local workspace is preserved; an authenticated online sign-in is still required before cloud operations can resume.

Network failures do not clear auth tokens, delete pending uploads, or invalidate the local encrypted document cache. Existing approval and role validation remain in place.

## Pending uploads

The existing `syncOfflineUploads()` implementation and `pendingUploads` store were not replaced. Reconnection calls the existing queue synchronizer after session identity and backend reachability checks. The queue remains the source of truth for pending uploads and is not cleared by this change.

## Ed25519 key verification

- Frontend constant retained exactly: `KagHtN5h3Bosagi6LyweAbuHelUmS2ZO7Tbss1vYS9Q=`.
- Frontend Ed25519 signature verification remains enabled.
- Supabase Edge Function signing logic and secret name `DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK` were not changed.
- The bundled `offline_private.pem` derives public key `wAnHO2G1lFyAtCpe4C2lHcL5EXKtDY8aKp/9KMZWchU=`, which does **not** match the required frontend key. The actual Supabase Edge Function secret is not present in this project archive, so its match cannot be verified here.
- The mismatching PEM is intentionally excluded from the deliverable ZIP so a private signing key is not distributed. No new key was generated and no signing secret was changed. The correct matching private JWK must be confirmed and configured securely in Supabase before device authorization provisioning can be considered verified.

## Tests performed

- Original ZIP integrity check passed before extraction.
- Static source review performed for document loading, IndexedDB stores, offline authorization, preview, upload queue, service worker, and Edge Function signing code.
- `node --check` passed for the combined inline JavaScript extracted from `index.html`.
- `node --check` passed for `scripts/verify-offline-key.mjs`.
- `git diff --check` passed.
- Static checks confirmed the exact required frontend key is present once, offline preview routes to the cached preview handler, and offline download routes to the cached download handler.
- The original archive passed its ZIP integrity check. The final archive is separately checked before delivery.
- No live Supabase authentication, Storage, RLS, Edge Function, browser-offline, or end-to-end upload test was possible from this environment. Those scenarios must be tested in the deployed app with a real approved account and a configured matching Edge Function secret.

## Remaining configuration / manual steps

1. Obtain the correct existing private JWK corresponding to the required public key through the project's secure key-management process.
2. Set `DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK` in Supabase Edge Function secrets; do not place it in frontend files or the ZIP.
3. Redeploy `docukeep-offline-access` only after the matching key has been verified.
4. Test the five requested scenarios in a real browser and Supabase project, including user-to-user public/private visibility and duplicate-upload behavior.

No database migration is required for this update.
