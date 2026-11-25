DOCUKEEP UPLOAD CONNECTIVITY FIX
=================================

What changed
------------
1. Replaced the strict Auth health endpoint check with a Supabase REST API
   reachability probe. An HTTP 4xx response means the Supabase host responded;
   it is not treated as an offline condition. Real Auth, Storage and database
   operations now report their own authorization and API errors.
2. A true browser offline state is the only condition labeled "Waiting for
   Internet". Supabase server unavailability is queued as a retry, and upload
   failures retain the backend's error message instead of being mislabeled
   as offline.
3. Added a distinct "Processing" queue state after Storage upload and before
   the documents database upsert/confirmation.
4. Improved P0001 diagnostics shown to the user and retained the actual
   backend message (truncated) in the queue.
5. Bumped the service-worker shell cache version so clients fetch the updated
   application code.

Important deployment / verification limits
-------------------------------------------
This source archive does not contain Supabase project access, live database
results, credentials, or test accounts. Therefore no live upload, RLS policy,
bucket, trigger, or role test can honestly be claimed as completed here.

Before production rollout:
- Deploy the updated index.html and sw.js together.
- In the Supabase SQL Editor, run docukeep_upload_diagnostics.sql and inspect
  the trigger/function definitions, document constraints, RLS policies,
  bucket size/MIME settings, and approved role/status values.
- If the approved-owner INSERT policies in
  docukeep_upload_permissions_migration.sql are absent, review and apply that
  additive migration in the existing project. Do not make the bucket public
  or disable RLS. Confirm the actual profiles.status values and any existing
  policies first; this migration expects status='approved' and roles student,
  teacher, staff.
- For P0001, inspect the exact raising trigger/function returned by the
  diagnostics query. Do not remove or bypass the quota guard. Correct the
  function only after confirming its intended quota rules and schema.
- Test with real approved student, teacher and staff accounts. This archive
  cannot simulate Supabase authentication or validate server-side RLS.

Static checks performed
-----------------------
- JavaScript syntax check passed for the inline application script.
- JavaScript syntax check passed for sw.js.
- Reviewed existing IndexedDB queue, upload controls, XHR Storage upload,
  document upsert/confirmation and service-worker sync messaging.


STORAGE QUOTA METADATA TIMING FIX (2026-11-25)
------------------------------------------------
If uploads fail with “The uploaded file size could not be verified.”, apply
docukeep_storage_quota_metadata_fix.sql in the Supabase SQL Editor. Supabase
Storage can create an initial authorization/probe row before final size metadata
is available, then update the row after the object upload completes. The previous
BEFORE INSERT trigger rejected that initial row. The corrected function defers
quota evaluation until size metadata is available and still enforces the quota
on the completed metadata update. It retains account-folder ownership checks,
advisory locking, and the 200 MB Free / 20 GB active Premium limits.

For new installations, docukeep_tutorial_storage_migration.sql has also been
updated with the corrected function. Existing installations should run the
standalone docukeep_storage_quota_metadata_fix.sql migration once.
