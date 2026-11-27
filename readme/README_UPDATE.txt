DOCUKEEP UPDATE — PROFILE CUSTOMIZATION AND DIRECT UPLOAD

Files:
- index.html: updated DocuKeep application.
- docukeep_profile_direct_upload_migration.sql: required Supabase profile customization migration.

IMPORTANT SETUP:
1. Open Supabase Dashboard > SQL Editor.
2. Run docukeep_profile_direct_upload_migration.sql.
3. Deploy the updated index.html and keep the existing Logo.png, manifest.webmanifest, icons, and sw.js files.
4. Test with a normal approved student/teacher account and a staff account.

CHANGES:
- Fixed the upload crash caused by missing legacy dashboard counters (#total, #pending, #approved, #recent).
- Uploaded documents are inserted with status "approved" so they are available without a staff document-review step.
- Document cards open the full-screen document viewer. PDFs and images display in the viewer; unsupported file types show an Open Original File link and Download action.
- Added My Profile page with editable display name, unique username, department/section, and optional HTTPS profile picture URL.
- Profile changes use a SECURITY DEFINER RPC that updates only display-profile fields. Users cannot change their role, email, or account approval status through this feature.
- Student/teacher account approval is unchanged. Staff registration and role permissions are unchanged.

NOTES:
- Existing documents with pending status are not automatically modified.
- A profile picture URL must be publicly accessible over HTTPS for it to display.
- The database migration adds username uniqueness and the secure profile-update RPC.
- This is a client-side web app; never put a Supabase service_role key in index.html.
