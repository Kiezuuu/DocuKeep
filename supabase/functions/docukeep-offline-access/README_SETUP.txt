DOCUKEEP OFFLINE ACCESS SIGNING KEY SETUP

1. Generate a dedicated Ed25519 key pair on a trusted administrator computer:
   node scripts/generate-offline-signing-keys.mjs
2. Copy the printed PRIVATE_JWK value into Supabase Edge Function secrets only:
   supabase secrets set DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK='<PRIVATE_JWK_JSON>'
   Never commit or upload the private JWK to GitHub, the website, or this ZIP.
3. Copy PUBLIC_KEY_BASE64 into OFFLINE_ED25519_PUBLIC_KEY in index.html.
4. Deploy: supabase functions deploy docukeep-offline-access
5. Ensure SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are available to Edge Functions.
6. Test with an approved student/teacher account. Staff accounts are deliberately denied offline authorization. No database migration is required.

The signing key pair is unique to this deployment. If regenerated, update the public key in index.html and deploy the new private JWK secret together. Existing packages signed by the old key will no longer verify.
