# DocuKeep — Automatic Offline Login (Option B revision)

## Behavior

- Registration and email verification remain online-only through the existing Supabase Auth flow.
- After a successful online login, DocuKeep checks the existing `profiles` row and automatically requests a device-bound, Ed25519-signed offline authorization.
- The authorization is valid for exactly seven days or less and contains only the `cached_documents:read` capability. It is not a Supabase access/refresh token and does not create a Supabase session.
- A device that has never completed a successful online sign-in cannot receive authorization while offline. Every new device must connect and sign in online once.
- The browser stores the signed credential, a non-extractable P-256 device private key, and a non-extractable AES-GCM data key in the existing `docukeep-offline-v1` IndexedDB database. The signed credential includes a thumbprint of the device public key.
- Offline login verifies issuer, audience, version, account binding, device-key thumbprint, role, permission set, signature, issue time, and expiry before opening the limited Offline Workspace.
- Only documents that were visible to the user under the existing Supabase RLS rules and successfully cached on this device are listed offline. Documents uploaded by other users can be cached when the signed-in user is allowed to access them. Uncached files are never fetched while offline.
- Accessing a document through the existing preview or download flow also attempts to save an encrypted local copy. The existing “Save for offline” action remains available for documents visible to the current account.
- The existing upload form remains available from the Offline Workspace. Its unchanged submit handler stores offline selections in the existing `pendingUploads` queue; it does not send them to Supabase while offline.
- Offline mode is read-only for cloud operations. It does not expose staff/admin controls or claim that Supabase authenticated the offline session.
- When connectivity returns, the offline workspace closes. The user must sign in online; the existing `loadProfile` checks approval and roles before online features and the existing upload queue synchronization resume.

## Supabase Edge Function deployment

The existing function name is retained:

```bash
supabase functions deploy docukeep-offline-access
```

The function requires the existing standard Supabase Edge Function environment values:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server-side only; never put it in frontend files)
- `DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK` (private Ed25519 JWK; server-side secret only)

If the signing secret has not been configured, generate a key pair on a trusted administrator computer:

```bash
node scripts/generate-offline-signing-keys.mjs
```

Set the printed private JWK as a Supabase secret. Copy only the matching public key into `OFFLINE_ED25519_PUBLIC_KEY` in `index.html`. Never commit the private key. If an existing deployment already uses the public key currently in `index.html`, keep the matching private secret; do not generate a new pair unnecessarily.

The Edge Function validates the current Supabase bearer token, confirmed email, approved profile, existing role rules, and device public key before signing. Deploy the function after updating it. No database migration or new table is required.

## Database and upload preservation

- No SQL migration is included or required for this revision.
- The existing IndexedDB database name, version, `pendingUploads` store, upload queue records, retry logic, and upload synchronization implementation are not changed.
- The existing `offlineAccess` and `offlineDocuments` stores are reused. No second database or upload queue is created.
- Existing Supabase RLS policies and Storage permissions remain the authority for online document visibility and cache downloads.

## Deployment

1. Back up the currently deployed DocuKeep project.
2. Deploy the updated `docukeep-offline-access` Edge Function.
3. Confirm the `DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK` secret matches the public key in `index.html`.
4. Deploy the updated project files, including `index.html` and `sw.js`, to the same hosting location.
5. The service-worker shell cache was advanced to `docukeep-shell-v9`; clients should receive the new application shell after the worker update.
6. Have each user sign in online once on every device they want to use offline. Provisioning is automatic after existing account approval checks pass.

## Security limitations

- A device without prior online provisioning cannot authenticate offline.
- While disconnected, account revocation, password changes, role changes, approval changes, and permission changes cannot be checked. The signed authorization can remain usable until its expiry.
- The seven-day expiry is checked against the device clock. A user who controls the device can manipulate its clock; browser software cannot provide a fully trusted offline clock.
- Legacy Option B document cache blobs were encrypted using a user-entered passphrase-derived key. Since the revised workflow intentionally removes passphrases, those old encrypted blobs cannot be automatically decrypted/migrated. They are not deleted, but the user must access/cache those documents again while online to create new device-key-encrypted copies.
- IndexedDB is not a hardware-backed secure enclave. Non-extractable WebCrypto keys make casual extraction harder, but malware, a compromised browser, malicious extensions, XSS, or copying an entire browser profile may expose or clone local access.
- Offline access is limited to cached documents. It never grants cloud access, upload authorization, admin access, or a Supabase session.

## Checks performed on this package

- Inline application JavaScript syntax check with Node.js.
- Edge Function TypeScript source reviewed for token/profile/device-key checks and Ed25519 signing.
- Manual import/export controls and handlers removed from the app UI/source.
- Confirmed the upload queue store remains named `pendingUploads`; byte-for-byte comparisons against the source ZIP show the queue synchronization function and upload form submit handler are unchanged.
- Confirmed the IndexedDB database name and version are unchanged; no migration was added.

## Tests still requiring deployment/browser accounts

The following cannot be fully verified in this packaging environment: live Supabase login/registration, Edge Function invocation and signing-secret match, pending/rejected-account denial against the deployed database, actual multi-device offline login, offline file rendering across browsers, and real upload queue resumption. Run the checklist in the handoff notes before production rollout.
