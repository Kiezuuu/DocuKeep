DOCUKEEP: RESTORE EMAIL CONFIRMATION + STAFF APPROVAL

WHAT THIS UPDATE DOES
- Restores the requirement for users to confirm their email address through the Supabase confirmation link.
- Keeps the existing staff approval requirement. Email confirmation does not automatically approve an account.
- Shows a clear warning telling users to check Gmail Inbox, Spam, Junk, and Promotions for the confirmation link.
- Adds a Resend confirmation email action after registration or when login reports an unconfirmed email.
- Keeps Forgot Password and the existing password-reset flow unchanged.
- Keeps the existing app layout and other features.

REQUIRED SUPABASE DASHBOARD SETTING
1. Open the same Supabase project used by DocuKeep.
2. Go to Authentication > Sign In / Providers > Email (the exact menu wording may vary).
3. Turn ON Confirm email.
4. Save the setting.

IMPORTANT
- Users must complete BOTH steps: confirm their email and wait for staff to approve their DocuKeep profile.
- Existing unconfirmed accounts should use the Resend confirmation email action or the confirmation action in Supabase Authentication > Users.
- Do not manually edit auth.users using SQL.
- Password recovery remains separate and still uses Supabase's password-reset email.
- The website files cannot change the live Supabase dashboard setting.

DEPLOYMENT
Replace the current website files with the contents of this ZIP and push the changes to the existing GitHub repository. Then turn ON Confirm email in the Supabase dashboard.
