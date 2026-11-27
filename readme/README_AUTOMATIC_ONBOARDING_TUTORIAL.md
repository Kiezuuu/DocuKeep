# DocuKeep — Automatic New User Onboarding Tutorial

## What changed

- Repaired and expanded the existing first-login tutorial into 10 steps based on the actual DocuKeep dashboard, sidebar, document library, upload form, tracking panel, folder form, People directory, notification/profile header, and existing offline upload queue.
- Added a live spotlight effect around the selected interface element, dimmed surrounding content, automatic scrolling, and a responsive instruction panel that positions itself away from the highlighted control.
- Added Previous, Next, Skip, progress, and final Finish Tutorial controls.
- Skip saves the current step and `skipped` status without completing the tutorial. The dashboard reminder remains available to continue later.
- Tutorial progress is account-scoped by Supabase `user_id` and stores status, current step, completed step indexes, start date, completion date, and update time. A local per-account copy supports recovery if a save is temporarily deferred.
- Existing completed records remain completed.
- Added signup-time enrollment for accounts created after the new migration is installed. Existing accounts are not backfilled or automatically enrolled.

## Files changed

- `index.html`
- `supabase/docukeep_onboarding_auto_enrollment_migration.sql` (new additive migration)
- `readme/README_AUTOMATIC_ONBOARDING_TUTORIAL.md` (this file)

## Required Supabase step

1. Back up the Supabase project.
2. Confirm `supabase/docukeep_onboarding_migration.sql` has already been applied. It creates `public.docukeep_onboarding_progress` and its user-owned RLS policies.
3. Run `supabase/docukeep_onboarding_auto_enrollment_migration.sql` in the Supabase SQL Editor.
4. Deploy the updated `index.html` while retaining the existing project assets and paths.
5. Test with a newly registered account after the migration is installed.

The new migration adds progress columns and an `AFTER INSERT ON auth.users` trigger. It creates only a `not_started` onboarding row for each account registered after installation. It does not alter email confirmation, profile approval, authentication, role, or permission checks. The tutorial is launched only after the existing sign-in/profile-loading path has accepted the user's approved profile.

## Existing account behavior

Accounts already present when the migration is installed are intentionally not backfilled and have `auto_enrolled = false` by default. They are not forced into the first-time walkthrough. The existing Replay Tutorial control remains available in the profile menu.

## Testing status

Static JavaScript syntax validation and source-level checks passed. This package has not been connected to the live Supabase project and no real signup, email verification, staff approval, browser spotlight, multi-device, or two-account isolation test has been executed. Complete the manual test checklist in the project request after applying the migration and deploying the frontend.

## Notes

- Progress is stored separately for each Supabase auth user ID.
- The current step is zero-based in the database (`0` is the first step).
- `completed_steps` is an integer array of zero-based step indexes.
- The tutorial does not introduce new document, sharing, People, notification, or offline functionality. It only describes the existing features.
