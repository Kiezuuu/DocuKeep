DOCUKEEP SIGNUP FIX

Cause identified in the supplied project:
- The signup page required teachers to use @deped.gov.ph.
- The current database signup trigger function in docukeep_account_notifications_migration.sql requires BOTH teachers and students to use @gmail.com.
- That policy mismatch can cause Supabase Auth to return the generic "Database error saving new user" when the database trigger rejects a teacher registration.

Changes:
- Teacher signup frontend now accepts personal Gmail, matching the existing intended policy and database trigger.
- Signup error display now logs and displays the actual returned error message for diagnosis.
- The older docukeep_migration.sql trigger function was aligned to the same Gmail policy.
- Added docukeep_signup_fix_migration.sql to update the function in the already deployed Supabase database.

Apply:
1. Back up your Supabase project.
2. Open Supabase Dashboard > SQL Editor.
3. Run docukeep_signup_fix_migration.sql.
4. Deploy the updated website files.
5. Try creating a new teacher account using a Gmail address.

If the error persists:
- In Supabase Dashboard > Logs > Auth/Postgres, inspect the exact database error at the time of signup.
- Run the commented diagnostic query in the migration to identify Auth triggers.
- Do not disable RLS or remove triggers as a workaround. The actual failing trigger/constraint must be fixed.
