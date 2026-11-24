DOCUKEEP: LOGIN AFTER STAFF APPROVAL (NO EMAIL CONFIRMATION LINK)

WHAT THIS UPDATE DOES
- Keeps the existing staff approval process: new student/teacher profiles are created with status = pending.
- Users can sign in only after staff changes their profile status to approved.
- Updates the registration message so users are told to wait for staff approval, not to click an email link.
- Keeps the existing Supabase password reset flow unchanged.
- Does NOT put a Supabase service_role key in the website.

REQUIRED SUPABASE DASHBOARD SETTING
This part cannot safely be changed by browser JavaScript or by the profile approval RPC. Supabase Auth blocks password login for unconfirmed email addresses before DocuKeep can check the profile status.

1. Open the SAME Supabase project used by DocuKeep.
2. Go to Authentication > Sign In / Providers > Email (the wording may vary slightly).
3. Turn OFF the Confirm email setting.
4. Save the setting.
5. Deploy the updated website files from this package to the existing GitHub Pages repository.

RESULT FOR NEW REGISTRATIONS
- Supabase creates the account without requiring an email confirmation link.
- DocuKeep creates the profile as pending.
- Before approval, sign-in is blocked by DocuKeep with an awaiting staff approval message.
- After staff approves the account in the Staff Panel, the user can sign in immediately with their registered email and password.

EXISTING UNCONFIRMED ACCOUNTS
Turning Confirm email OFF does not necessarily confirm accounts that were already created as unconfirmed. For each affected existing account, an administrator must open Supabase Dashboard > Authentication > Users, select the user, and use the dashboard's confirm/verify email action if available. Do not edit auth.users directly with SQL. After that one-time confirmation, the user can sign in once their DocuKeep profile is approved.

SECURITY NOTES
- Keep DocuKeep's profiles.status approval check in place. Do not remove it.
- Keep the Supabase project private settings and RLS policies.
- Never put the service_role key in index.html, JavaScript, or GitHub.
- Disabling email confirmation means Supabase no longer verifies that a registrant controls the entered email address. Staff approval becomes the app's access gate, so staff should verify registration requests before approving them.
- Password reset still uses Supabase resetPasswordForEmail and its email link. This update does not change password reset.

TEST CHECKLIST
1. Register a new student or teacher with Gmail.
2. Confirm the profile appears as pending in the Staff Panel.
3. Try signing in before approval: it should be blocked with the awaiting approval message.
4. Approve the account in the Staff Panel.
5. Sign in again: it should open DocuKeep without an email confirmation link.
6. Test Forgot Password separately to confirm the reset email still works.

This package cannot change the Supabase Dashboard setting or verify the live Supabase project. The dashboard steps above are required.
