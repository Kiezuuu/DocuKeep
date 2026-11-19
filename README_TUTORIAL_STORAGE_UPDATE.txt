DOCUKEEP TUTORIALS + STORAGE UPDATE

FILES
- index.html: updated DocuKeep frontend. Deploy this as the site's index.html.
- docukeep_tutorial_storage_migration.sql: additive Supabase database + Storage migration.
- Existing Logo.png, manifest.webmanifest, sw.js, and icons remain unchanged.

WHAT CHANGED
- Removed the Classroom page, navigation item, related browser-side invite/join/create code, and classroom-only sharing choices.
- Added a Tutorials page where approved signed-in users can create, publish, edit, and delete their own tutorials.
- Tutorial fields: title, description, category, written content, cover image, and multiple file attachments.
- Added private tutorial file storage with owner-based paths and row-level security.
- Added account-wide storage usage reporting based on actual Supabase Storage object metadata across docukeep-files and docukeep-tutorials.
- Free quota: 200,000,000 bytes (200 MB decimal).
- Premium quota: 20,000,000,000 bytes (20,000 MB decimal / 20 GB decimal).
- Storage upload limits are enforced by a database trigger on storage.objects, not only by the browser.
- Existing premium payment requests remain staff-verified. Premium storage is not activated by clicking Upgrade; the existing authorized approval flow must activate the entitlement.

INSTALLATION
1. Back up your Supabase project.
2. Open Supabase SQL Editor.
3. Run docukeep_tutorial_storage_migration.sql after your existing DocuKeep, folder, and subscription/payment migrations.
4. Confirm the private buckets docukeep-files and docukeep-tutorials exist and that the Supabase project/storage provider plan allows the intended maximum object size and total capacity.
5. Deploy the updated index.html to the existing website root. Keep Logo.png, manifest.webmanifest, sw.js, and icons/ in their existing locations.
6. Hard-refresh the website or clear the site's cached app shell if an older service-worker version continues to serve the previous index.html.

IMPORTANT NOTES
- No service_role key is added to the browser. The existing Supabase publishable/anon key and signed-in user session are retained.
- The database migration has been authored against the schema visible in the supplied project package, but it has not been executed against your live Supabase project. Apply it in a backed-up project and review any SQL error before deployment.
- Supabase provider-level upload limits and project storage capacity are separate from DocuKeep's per-account quota. The SQL raises the bucket file-size setting to 20 GB, but the Supabase plan must also permit the desired size/capacity.
- Existing document files are included in each user's quota by counting actual objects in docukeep-files. Tutorial attachments and covers are counted in docukeep-tutorials. Profile pictures and payment receipts are intentionally separate from the document/tutorial quota. Existing staff document deletion remains supported; tutorial file deletion is owner-only.
- Existing document-sharing policies are retained. The removed category and its browser-side workflow are no longer present in index.html; legacy group tables/migration files are retained as historical database objects and are not dropped.
- Test with two separate accounts: upload until near quota, verify over-limit upload rejection, delete a file, verify the freed space, and verify one account cannot read/delete another account's private tutorial file.


POST-MIGRATION TEST CHECKLIST
1. Free account: verify the dashboard says 200 MB total and shows used/available values.
2. Free account: create a tutorial with a cover and attachments; confirm the tutorial appears under Explore and My Tutorials.
3. Free account: attempt an upload larger than remaining capacity; confirm Storage rejects it and the dashboard usage does not increase.
4. Free account: edit a tutorial, replace its cover, and delete a tutorial; confirm deleted objects disappear from Storage and available space increases.
5. Premium account: approve a test subscription request as staff (or use the authorized entitlement approval process); verify the account shows PREMIUM and 20 GB total. Clicking Upgrade without approval must leave it on Free.
6. Premium account: upload/delete tutorial files and confirm actual usage and remaining capacity update.
7. Isolation: sign in as Account A and Account B. Confirm B cannot select, download, update, or delete A's private tutorial assets. Published tutorials may be read by signed-in users according to the public tutorial policy.
8. Regression: verify document upload, review, sharing with individual users, profile editing, and staff document deletion still work.

The above checklist is not marked complete by this package: it requires execution against your own Supabase project and two real test accounts.
