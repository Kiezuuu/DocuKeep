DOCUKEEP — ACCOUNT, UPLOAD, NOTIFICATION & WEB PUSH UPDATE

SOURCE
- Built on the latest saved DocuKeep_Onboarding_Updated.zip (19 Nov 2026).
- Retains the existing single-page app, Supabase Auth, Postgres, Storage bucket, document tables, profile system, and staff administration.
- Static assets omitted from the latest minimal ZIP were restored from the preceding DocuKeep_Updated.zip without replacing the newer index.html.

FRONTEND CHANGES
- Teacher registration/login now accepts any syntactically valid email address; student registration remains Gmail-only.
- Public registration still permits only student/teacher roles. New profiles remain pending until staff approval. Teacher email addresses are no longer restricted to a school-issued domain or Gmail.
- Uploads use the authenticated Supabase Storage endpoint with per-file transfer progress; file metadata is inserted only after the storage upload succeeds. Teacher uploads are recorded as pending review; student uploads retain their existing approved behavior.
- Notification bell is positioned beside the profile menu, displays an unread count, opens a responsive dropdown, supports mark-read/mark-all-read, and refreshes through Supabase Realtime.
- Staff account review now asks for confirmation and requires a rejection reason.
- Document review uses a staff-checked database RPC rather than a direct client-side update.
- Service worker displays push notifications and opens the relevant DocuKeep page when clicked.

DATABASE INSTALLATION
1. Back up your Supabase project.
2. Apply docukeep_account_notifications_migration.sql AFTER the existing DocuKeep core, role-management, storage, and onboarding migrations.
3. Confirm the existing `is_docukeep_staff()` helper and the current `profiles`, `documents`, and `docukeep_notifications` schemas are present. The migration uses these existing objects.
4. Confirm the signup trigger already calls public.handle_docukeep_signup(); the migration replaces that function body to allow Gmail for student/teacher registrations.
5. Confirm the storage bucket `docukeep-files` is private and its existing RLS policies allow authenticated approved users to upload only under their own user-id folder.

WEB PUSH SETUP — REQUIRED FOR BACKGROUND DELIVERY
Real push delivery cannot be activated by static GitHub Pages files alone. The included Supabase Edge Function must be deployed and configured:

1. Generate a VAPID key pair using `npx web-push generate-vapid-keys` on a trusted computer.
2. Set Supabase Edge Function secrets:
   - VAPID_PUBLIC_KEY
   - VAPID_PRIVATE_KEY
   - VAPID_SUBJECT (for example mailto:your-admin-email@example.com)
   - DOCUKEEP_WEBHOOK_SECRET (a long random secret)
   Supabase provides SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to Edge Functions.
3. Replace `REPLACE_WITH_VAPID_PUBLIC_KEY` in index.html with the generated VAPID public key.
4. Deploy `supabase/functions/docukeep-push/index.ts` as the `docukeep-push` function.
5. In Supabase Database Webhooks, create an INSERT webhook for public.docukeep_notifications targeting the deployed Edge Function. Add header `x-docukeep-webhook-secret` with the exact DOCUKEEP_WEBHOOK_SECRET value. Send the inserted row as the request body.
6. Redeploy the website over HTTPS. On each device, sign in and choose Notifications > Enable push; grant browser permission.
7. Test with a second account: create a notification by approving/reviewing an account/document and confirm a push arrives on the subscribed device.

IMPORTANT PUSH LIMITATIONS
- Web Push requires HTTPS (GitHub Pages qualifies), browser/device support, user permission, a deployed Edge Function, VAPID keys, and the database webhook. iOS web push requires the site to be added to the Home Screen on supported iOS versions. The app cannot bypass OS/browser notification settings.
- This package includes the delivery code and subscription storage, but push delivery remains inactive until the Supabase secrets, Edge Function deployment, Database Webhook, and public VAPID key are configured as above.

TESTING / DEPLOYMENT
- JavaScript syntax should be checked before deployment.
- SQL has not been run against the live Supabase project; apply it only after backup and review the Supabase SQL Editor result.
- Test Gmail teacher signup, email confirmation, pending status, staff approval/rejection, login gating, teacher upload, file review, in-app notifications, and push on an Android/iOS device.
- Existing provider-level Storage limits still apply. The frontend's current per-file limit remains 25 MB.
