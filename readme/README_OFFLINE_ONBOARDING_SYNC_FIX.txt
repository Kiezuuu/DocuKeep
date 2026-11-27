DOCUKEEP — OFFLINE/ONLINE, FILE CACHE, ONBOARDING AND APPROVAL REPAIR

CHANGES
- Supabase client keeps the existing persistSession/autoRefreshToken configuration. Session restoration now attempts the persisted Supabase session and falls back to the already provisioned, signed device authorization if the backend is unavailable.
- Reconnect no longer signs the user out of offline mode. It verifies Supabase reachability, validates the same account's current session/profile, then restores cloud features and runs the existing upload queue. If validation fails, the encrypted local view remains active.
- A failed document-list refresh now falls back to the account-scoped encrypted IndexedDB cache instead of leaving an empty list.
- Files currently visible under Supabase RLS are cached locally after a successful list refresh. The cache is reconciled against the latest authorized server list only after a successful database read; cached files no longer visible to the account are removed from this device.
- IndexedDB upgrades in place to version 5, preserving the existing pendingUploads, offlineAccess, and offlineDocuments stores while adding separate personal-file, public/shared-file, and successfully-synchronized indexes.
- Selecting a file while offline immediately stores its actual File blob in the existing pendingUploads store as a draft; submitting the upload form updates that same queue item instead of creating a duplicate. Draft selections wait for the required upload details before automatic transfer. Pending upload jobs retain file blobs until Supabase Storage and document-row confirmation succeed.
- Tutorial skip now records `skipped`, never `completed`; step progress is stored locally and in the existing Supabase onboarding table. Users resume at their last step and see a dashboard Continue Tutorial reminder until final-step completion. Existing completed users remain completed.
- Existing signup trigger already creates student/teacher profiles as `pending`; existing profile loading blocks non-approved users; existing staff review RPC and RLS migrations are retained. No automatic approval path was added.

FILES MODIFIED
- index.html
- sw.js (cache version only)
- supabase/docukeep_onboarding_migration.sql
- supabase/docukeep_approval_enforcement_migration.sql
- readme/README_OFFLINE_ONBOARDING_SYNC_FIX.txt

DATABASE
- Apply the additive docukeep_onboarding_migration.sql update in Supabase SQL Editor. It adds status/current_step/skipped_at to the existing table and preserves completed_at.
- Apply docukeep_approval_enforcement_migration.sql after the existing core/role migrations. It adds restrictive RLS gates to protected data and the private file bucket while retaining own-profile reads for pending users.
- No tables, users, files, buckets, roles, or existing records are deleted.
- Keep the docukeep-files bucket private. Do not add a service-role key to frontend code. Existing signup/approval and RLS migrations remain required.

LIMITATIONS / TESTS
- Static syntax and archive checks should be run locally before deployment. Live Supabase RLS, real account approval, network interruption, browser storage quota, and actual file transfer require the deployed project and real accounts.
- Automatic caching downloads all files currently visible to the signed-in user; large libraries may consume significant device storage. Browser quota/eviction still applies. Files never cached before a disconnect cannot be opened offline.
- Standard Supabase Storage POST uploads are not byte-resumable. The existing queue retries a failed transfer from the beginning while retaining the original local blob; exact byte-offset resume requires TUS/resumable uploads.
- A browser cannot enforce immediate permission revocation while fully offline. Revocations are reconciled the next time the server is reachable; offline authorization remains bounded by the existing signed authorization expiry.
