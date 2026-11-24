DOCUKEEP — CURRENT LIBRARY ZIP UPDATE

SOURCE
- Based on the latest previously delivered DocuKeep_UI_Fixes_2026-11-25.zip, preserving the prior onboarding and UI corrections.
- Existing single-page application, Supabase project configuration, logo, private storage buckets, database tables, and account approval workflow are retained.

CHANGES IN THIS UPDATE
1. Teacher email validation now accepts any syntactically valid email address in registration, sign-in, and profile loading. Student registration remains Gmail-only. Staff approval and email confirmation are unchanged.
2. Updated docukeep_account_notifications_migration.sql so the signup trigger accepts valid non-Gmail teacher addresses while retaining the student Gmail rule. The staff role-management RPC now enforces Gmail only for student accounts.
3. Teacher document uploads are inserted with pending review status; student/staff uploads retain the existing approved status.
4. Fixed a queued-upload progress callback that referenced variables outside its scope. Queue progress now reports the queued file name and queue position. Added a per-file retry action for failed queued uploads.
5. Added a responsive notification bell beside the profile menu, unread count, compact dropdown, mark-read/mark-all-read actions, and a user-filtered Supabase Realtime subscription. Notifications remain backed by the existing docukeep_notifications table.
6. Added a 9-step first-login onboarding tour with Back, Skip, Next, Finish, progress indicator, and a Replay Tutorial action in the profile menu. Completion is stored in the existing docukeep_onboarding_progress table.
7. Increased the service-worker app-shell cache version so deployed browsers refresh the updated shell.

FILES MODIFIED
- index.html
- sw.js
- docukeep_account_notifications_migration.sql
- README_ACCOUNT_NOTIFICATIONS_UPDATE.txt

DATABASE / DEPLOYMENT
- No database schema changes were introduced by this update. The package already contains docukeep_onboarding_migration.sql and docukeep_account_notifications_migration.sql.
- Back up Supabase first. Re-run the updated docukeep_account_notifications_migration.sql in Supabase SQL Editor so the signup trigger and staff role-management function are updated.
- Confirm docukeep_upload_permissions_migration.sql has been applied so approved teachers/students/staff can upload to their own private Storage path and insert their own document metadata.
- Confirm docukeep_onboarding_migration.sql has already been applied; if not, apply it before testing the first-login tour.
- Keep docukeep-files and docukeep-tutorials private. Do not make buckets public and do not add a service-role key to frontend code.
- Deploy index.html, sw.js, manifest.webmanifest, offline.html, Logo.png, icons/, and assets/ together to the existing GitHub Pages root.

VERIFICATION
- JavaScript syntax checks passed for the inline application script and sw.js. HTML was parsed with Python's HTMLParser; no duplicate element IDs were found.
- Static checks confirmed the old DepEd-only teacher email restriction is absent, the onboarding contains 9 steps, and there is one notification realtime subscription function and one queue retry handler.
- Live Supabase registration, account approval, file uploads, RLS, Realtime, push delivery, and offline synchronization were not executable in this environment and must be tested against the user's deployed Supabase project and GitHub Pages site.
- Real push notifications still require the VAPID secrets, deployed docukeep-push Edge Function, and database webhook described in README_ACCOUNT_NOTIFICATIONS_UPDATE.txt.

UI CORRECTIONS (25 NOV 2026)
- Removed the community tutorial publishing/management page and its Create Tutorials navigation item. The first-login onboarding walkthrough and Replay Tutorial action remain.
- Rebuilt the 9-step walkthrough navigation with independent Back, Skip Tutorial, Next, and Finish controls; safe handling for missing page targets; page-aware step navigation; progress updates; and persisted completion in docukeep_onboarding_progress.
- Removed Notifications and My Profile from the sidebar. Notifications now have one header bell beside the profile menu; the dropdown renders the complete user-scoped notification list, unread count, mark-read actions, and mark-all-read action.
- Updated notification sizing, text wrapping, scroll behavior, mobile positioning, and viewport-height limits.
- Refined sidebar icon sizing, hover/active behavior, focus outlines, and transitions without changing the existing destinations or branding.
- No database schema or RLS changes were made for these UI corrections. The existing docukeep_onboarding_migration.sql remains required for first-login completion tracking.

UI VERIFICATION
- Inline JavaScript syntax check passed with Node.js.
- Service worker JavaScript syntax check passed with Node.js.
- HTML parsing found no duplicate element IDs.
- Static checks confirmed no tutorial management UI/CRUD, no sidebar My Profile/Notifications/Tutorials entries, one header notification bell, and all four onboarding controls.
- Desktop/mobile layout rules were reviewed statically; live browser interaction and live Supabase notification/onboarding behavior still require deployment testing.


UPLOAD QUEUE + BUTTON ICON CORRECTIONS (25 NOV 2026)
- Updated the existing IndexedDB upload queue in place to version 3. Existing pendingUploads records are retained; queued files remain tied to their creator UUID.
- Added automatic serial queue processing after reconnect, focus/visibility return, and successful sign-in. The queue checks the authenticated Supabase user before processing and pauses the queue for re-authentication if the session is missing or belongs to another user.
- Added per-file real upload progress, status, Pause, Resume, and Cancel controls. Pause aborts the current standard Storage upload request while preserving the local file and last displayed progress. Resume retries the standard Storage POST from the beginning because this endpoint is not a resumable/TUS upload.
- Added bounded exponential retry for temporary network/server errors. Permanent quota, permission, and validation errors are retained as Upload Failed and are not automatically retried.
- Successful uploads are confirmed against the documents table before the local file blob is discarded. The Completed state is displayed briefly; stale completion markers are cleaned up. Failed metadata inserts trigger a best-effort cleanup of the exact Storage path when no document row exists. Stable document UUIDs and Storage paths keep retries idempotent.
- Fixed the sidebar hover rule that used the CSS background shorthand on the icon pseudo-element, which could clear the existing SVG data-URI background image. Button SVGs now use currentColor and remain visible across hover/focus/active/disabled states.
- Bumped the service-worker cache to v6 so deployed clients fetch the updated app shell.

DATABASE DIAGNOSTIC LIMITATION
- No database trigger/function/RLS migration was changed because this workspace does not contain a live Supabase schema snapshot or the actual Postgres exception detail. Bundled migrations contain several possible P0001 sources, including the document storage-quota trigger and document-folder ownership validation. Run docukeep_upload_diagnostics.sql and inspect the matching failed INSERT in Supabase Dashboard > Logs > Postgres before changing any database function. This preserves the current quota and security rules instead of guessing which validation raised the error.

TEST STATUS
- Local static validation covers JavaScript syntax, HTML parsing, duplicate IDs, queue action wiring, upload state handling, SQL diagnostic presence, and ZIP integrity. Live network interruptions, pause/resume/cancel timing, teacher/student/staff Supabase permissions, database trigger execution, Storage cleanup, and visual hover behavior require a deployed browser and Supabase project; they were not represented as manually tested here.
