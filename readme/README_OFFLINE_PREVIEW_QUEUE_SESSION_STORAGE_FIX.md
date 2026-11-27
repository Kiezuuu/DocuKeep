# DocuKeep — Offline Preview, Queue Cleanup, Session Persistence, and Storage Dashboard Fix

## Scope and preservation

This update is layered onto the existing DocuKeep project and the prior Offline Library/Reconnection fix. It preserves the existing HTML/CSS design, Supabase client and database schema, Storage bucket/policies, IndexedDB database and object stores, authenticated session flow, offline authorization format, and Ed25519 verification. No database migration or reset is included.

## Root causes found

1. **Preview:** The existing preview path used a signed remote Storage URL in online mode and only used the encrypted IndexedDB file bytes in offline mode. A document could therefore be cached but the online preview path did not prefer that local copy. The offline preview supported only a subset of formats and used a separate helper instead of a shared rendering path.
2. **Queue cleanup:** `markQueuedJobCompleted()` retained completed items in `pendingUploads` for ten seconds and only removed them later. The queue manager rendered those completed items during that period. The completion path needed to remain tied to successful Storage and database confirmation, not the 100% progress event.
3. **Idempotent retry:** `uploadJob()` returned immediately when a documents row with the same ID existed, without checking that the referenced Storage object remained available.
4. **Storage dashboard:** `refreshStorageDashboard()` called `warning.textContent` before checking whether `storageWarning` existed. The warning element is optional in some rendered views, so a missing node could throw and abort the rest of the refresh. Other storage fields were also updated without checking whether their nodes existed.
5. **Offline storage information:** The dashboard did not retain a per-account storage usage snapshot for offline display.

## Files modified

- `index.html`
  - Online preview and download now prefer a verified account-bound encrypted IndexedDB copy when one is available.
  - Offline preview uses the actual decrypted cached Blob. It does not attempt a remote Storage URL when offline.
  - Online preview falls back to a freshly fetched Storage object only when no valid cached file exists, then starts background cache hydration.
  - PDF, images, and supported text formats are rendered from the actual Blob. Unsupported formats are identified honestly; no placeholder is represented as a real preview.
  - Preview object URLs are replaced/revoked when another preview is opened and revoked when the preview closes. Download-only temporary URLs are also revoked.
  - Completed queue entries are removed immediately only after `uploadJob()` resolves. That function waits for successful Storage upload (or confirms an existing Storage object on idempotent retry) and reads back the database document row.
  - Pending, failed, interrupted, and paused jobs remain in the existing IndexedDB queue. Queue keys remain document/job IDs, preserving the existing deduplication behavior.
  - Storage dashboard updates now safely check each actual DOM element. Offline mode displays a per-account cached usage snapshot when one exists; online mode refreshes and saves the latest usage values.
  - Offline workspace storage-card child updates now tolerate optional/missing descendants.

- `readme/README_OFFLINE_PREVIEW_QUEUE_SESSION_STORAGE_FIX.md`
  - Documents root causes, implementation, validation, and limitations.

## Queue completion semantics

The XHR progress callback reaching 100% does not remove a job. The job remains active while the upload response and database registration are processed. The existing `uploadJob()` path confirms the Storage operation and then upserts and reads back the `documents` row. On a retry where the database row already exists, the code now creates a short-lived signed URL for the row's Storage path to confirm that the object is still present before treating the job as already complete. Only after `uploadJob()` resolves does `markQueuedJobCompleted()` remove the item from the active queue.

The existing project does not contain a separate durable completed-upload history store. Therefore this patch does not invent one or change the IndexedDB schema; completed items are removed from the active queue as requested. Existing pending file Blobs are not deleted during failure/retry paths.

## Session and reconnect behavior

The existing Supabase auth session restoration and automatic reconnect flow are retained. No token clearing, forced sign-out, session reset, approval bypass, or role change was introduced. Reconnection still verifies Supabase reachability and validates the existing authenticated user's profile/approval before resuming cloud operations. Offline-only sessions remain local-only until a valid Supabase session is available; this is existing security behavior, not a forced logout.

## Ed25519 security

The frontend constant remains exactly:

`KagHtN5h3Bosagi6LyweAbuHelUmS2ZO7Tbss1vYS9Q=`

The verification path remains enabled. No new key was generated and no Edge Function signing secret was changed. The project archive's PEM was excluded from the deliverable to avoid distributing private signing material. The earlier key mismatch finding remains unresolved: the private signing secret configured in Supabase must be independently checked against the required public key.

## Tests performed

- Inline JavaScript extracted from `index.html`: `node --check` passed.
- `scripts/verify-offline-key.mjs`: `node --check` passed.
- All storage dashboard element IDs referenced by the renderer were checked against the HTML; the current dashboard includes them, and the renderer now safely handles missing optional nodes.
- Static checks confirmed preview uses the encrypted local Blob path first when available, and does not call a remote signed URL in offline mode.
- Static checks confirmed completed queue removal occurs only after `uploadJob()` resolves; progress 100% alone does not remove a job.
- Static checks confirmed the required public key remains unchanged and signature verification remains present.
- Archive integrity is checked on the final ZIP.

### Not performed

A real browser with the deployed Supabase project was not available here. Therefore offline PDF/image rendering in the target browser, real Storage uploads, RLS/database confirmation, reconnect without refresh, refresh-time Supabase session restoration, and live storage RPC behavior have **not** been claimed as end-to-end passed. Test these with an approved account and actual cached documents before production deployment.

## Deployment notes

- No SQL migration is required for this patch.
- Deploy the updated static app files as usual.
- Keep the existing Supabase Edge Function secret private and verify that it corresponds to the required public key before relying on offline authorization provisioning.
