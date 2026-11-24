DOCUKEEP — CURRENT LIBRARY ZIP UPDATE

SOURCE
- Based on the latest Library archive DocuKeep(1).zip (modified 24 Nov 2026).
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
