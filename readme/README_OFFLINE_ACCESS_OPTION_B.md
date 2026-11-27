# DocuKeep — Option B: Secure Offline Access

## What was added

- A server-issued Ed25519-signed offline authorization package.
- AES-256-GCM encryption of the package with a separate passphrase-derived key.
- PBKDF2-SHA-256 (310,000 iterations) with a random 16-byte salt.
- Seven-day maximum authorization lifetime.
- Import/export of the encrypted JSON package.
- An isolated Offline Workspace with cached profile details and explicitly cached documents only.
- AES-GCM encryption of cached document bytes and metadata in IndexedDB.
- Existing IndexedDB upload queue preserved; the database is upgraded from version 3 to 4 and adds `offlineAccess` and `offlineDocuments` stores.
- Existing Supabase login, registration, verification, password reset, roles, approval checks, and online document code remain in place.

Approved student, teacher, and staff accounts may receive a limited offline package. Staff accounts receive no staff/admin controls or privileged offline actions; they can only use their cached profile and explicitly cached documents they own.

## Required one-time deployment setup

The feature will not issue packages until the signing key is configured. Do not skip this setup.

1. Install/use Node.js on a trusted administrator computer.
2. From the DocuKeep project root, run:

   ```bash
   node scripts/generate-offline-signing-keys.mjs
   ```

3. The script prints a private JWK and a public key. Keep the private JWK secret. Do not add it to this repository, frontend JavaScript, GitHub, or this ZIP.
4. Set the private JWK as a Supabase Edge Function secret:

   ```bash
   supabase secrets set DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK='PASTE_PRIVATE_JWK_JSON_HERE'
   ```

5. Copy the `PUBLIC_KEY_BASE64` value into `OFFLINE_ED25519_PUBLIC_KEY` in `index.html`, replacing `__DOCUKEEP_OFFLINE_PUBLIC_KEY__`.
6. Confirm the Supabase Edge Function environment has the standard `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` secrets. The service-role key is used only inside the Edge Function.
7. Deploy the function:

   ```bash
   supabase functions deploy docukeep-offline-access
   ```

8. Deploy the updated `index.html`, `sw.js`, and existing assets to the current DocuKeep hosting location. The service worker cache name is bumped to `docukeep-shell-v8` so clients can receive the updated app shell.

No SQL migration or new database table is required. The Edge Function reads the existing `profiles` record and checks `status = 'approved'`. It also verifies the Supabase user token and confirmed email. Staff is denied by design.

### Key rotation

Generate and deploy a new private key secret and public key together. Previously exported packages signed by the old key will stop verifying after rotation. Users must prepare and export a new package.

## How users enroll and transfer

1. Sign in normally through Supabase while connected.
2. Open Profile menu → Account Settings → Offline Access.
3. Enter a separate passphrase of at least 12 characters and confirm it.
4. Select **Prepare & Export Package**. The server checks the authenticated user and approved profile, signs a short-lived authorization payload, and the browser encrypts it.
5. Transfer the exported `DocuKeep-Offline-Access.json` securely to the other device.
6. On the other device, choose **Import Offline Access Package**, select the JSON file, and enter the same offline passphrase.
7. Select **Continue Offline** and enter the passphrase to unlock the local package.
8. While online on the original device, users can save their own documents for offline use from the document preview using **Save for offline**. The file and metadata are encrypted before storage in IndexedDB.

Import can be performed while offline as long as the DocuKeep app shell and public verification key are already cached on that device.

## Security model and limitations

- The package contains no plaintext account password and no Supabase access or refresh token.
- The private Ed25519 signing key exists only in Supabase Edge Function secrets. The browser contains only the public verification key.
- The browser verifies the Ed25519 signature after decrypting the package. AES-GCM authentication rejects modified ciphertext; Ed25519 rejects altered claims or forged packages.
- Offline authorization is a local capability, not a Supabase-authenticated session. Offline mode is visibly labelled and does not call privileged online functions.
- The package is intentionally transferable. It is not cryptographically bound to one physical device because that would conflict with importing it onto another device. A copied package can be used on any device that has the DocuKeep app and the passphrase until it expires.
- Browser IndexedDB is not a hardware-backed credential vault. Encryption protects stored package and cached document data at rest, but a compromised browser, malicious extension, XSS vulnerability, or malware running as the user may capture data while unlocked.
- Expiration is checked against the device clock. Browsers do not provide a trusted offline clock, so a determined user who controls the device may manipulate its clock. The seven-day lifetime is a practical control, not a guarantee against a device owner changing system time.
- Account revocation, role changes, and permission changes cannot be detected while disconnected. A revoked account may retain offline access until package expiration or until the user reconnects and is forced back through normal Supabase authentication.
- After reconnection, users must sign in online to revalidate account approval and current permissions. They should prepare a fresh package in Account Settings; the app does not silently re-encrypt a package because it does not retain the offline passphrase.
- Only explicitly cached documents owned by the user are available in this implementation. Public/shared documents and uncached files are not automatically downloaded for offline access.
- Existing queued uploads remain in the original upload store. Offline workspace does not expose administrator functions or add privileged offline operations.

## Verification checklist

### Local/static checks completed during packaging

- JavaScript syntax check of the complete inline application script.
- JavaScript syntax check of the Ed25519 key-generation script.
- Confirmed unique HTML element IDs for the new controls.
- Confirmed IndexedDB upgrade retains `pendingUploads` and adds only the two offline stores.
- Confirmed no private signing key or service-role key was added to frontend source.

### Required deployment/device tests (not performed by packaging)

- Configure the signing key secret and public key, deploy the Edge Function, and confirm approved student/teacher package issuance.
- Confirm pending/rejected/disabled users and staff cannot obtain a package.
- Export/import on a second browser/device.
- Verify wrong passphrase, altered ciphertext, altered signature, and expired package rejection.
- Save an owned document for offline use; disconnect internet; unlock Offline Workspace; open the cached file.
- Confirm an uncached file is not available offline.
- Confirm administrator controls are absent in Offline Workspace.
- Confirm the existing pending upload queue survives the IndexedDB upgrade and synchronizes after a normal online Supabase sign-in.
- Test browser refresh, private browsing restrictions, mobile browsers, and storage quota behavior.

**Do not treat offline access as production-ready until the Edge Function secrets are configured and these deployment/device tests pass.**
