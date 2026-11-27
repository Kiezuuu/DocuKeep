DOCUKEEP AUTOMATIC OFFLINE ACCESS — EDGE FUNCTION SETUP

Deploy:
  supabase functions deploy docukeep-offline-access

Required Edge Function environment values:
  SUPABASE_URL
  SUPABASE_ANON_KEY
  SUPABASE_SERVICE_ROLE_KEY
  DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK

The private Ed25519 JWK must remain in Supabase Edge Function secrets. Never put it in index.html, GitHub, or the project ZIP.

The frontend index.html contains only the matching Ed25519 public key in OFFLINE_ED25519_PUBLIC_KEY. Keep the existing private secret if it matches that public key. If there is no matching secret, generate a new pair with:
  node scripts/generate-offline-signing-keys.mjs

Then set the private JWK secret and replace only the frontend public key with the matching PUBLIC_KEY_BASE64 value. Deploy the function and frontend together.

After a successful online Supabase login and existing approved-profile checks, the app automatically provisions that browser/device. A device that has never signed in online cannot be provisioned offline. Credentials expire after seven days maximum.

No SQL migration is required. Existing pendingUploads IndexedDB storage and upload synchronization are preserved.
