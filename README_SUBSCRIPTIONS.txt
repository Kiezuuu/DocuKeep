DOCUKEEP PREMIUM SUBSCRIPTION UPDATE

FILES
1. index.html - replace the current website index.html with this file.
2. add_subscription_migration.sql - run in Supabase SQL Editor.

IMPORTANT SETUP
Run this SQL only AFTER your existing DocuKeep base setup and docukeep_migration.sql have been applied. It expects the existing profiles, documents, folders, groups, group members, document access, and entitlement tables/functions.

PREMIUM-ONLY FEATURES
The updated page locks these features for Free accounts and unlocks them only while the Premium entitlement is active and not expired:
- 128 GB account storage quota (subject to your Supabase project's actual storage capacity)
- Bulk upload
- Delete duplicate files (using matching SHA-256 fingerprints)
- Digital Document Tracker page
- Custom folder colors
- Group file access (database policies require Premium for the sharing owner and recipient)

FREE ACCOUNTS
- Can still upload one file at a time.
- Can still create folders using the default blue color.
- Cannot use bulk upload, duplicate deletion, the Digital Document Tracker page, custom folder colors, or group file sharing.

SUBSCRIPTION WORKFLOW
Users request Weekly (7 days), Monthly (1 calendar month), or Yearly (1 calendar year). The administrator contacts the user and receives payment directly. Staff must verify payment and activate the request in Staff Administration. Expiry is enforced using expires_at even if the scheduled expiry cleanup has not yet run.

ADMIN / PAYMENT
DocuKeep does not collect payments. Do not activate a subscription until payment has been verified. The user's student/teacher account role is not changed; Premium is a separate entitlement.

LIMITATIONS / DEPLOYMENT NOTES
- Supabase Storage itself must have sufficient capacity for 128 GB. The app cannot create provider storage capacity by itself.
- The existing per-file upload ceiling remains 25 MB unless separately changed in Supabase Storage.
- Group access database rules are enforced, but a full group creation/member-management interface is not included in this update.
- Digital Document Tracker is gated in the interface. Document status fields remain visible in My Documents because they are part of the existing document record view.
- The SQL trigger guards bulk-upload batch markers, custom folder colors, and duplicate deletion. Keep RLS enabled and do not expose the service_role key in index.html.
