-- DocuKeep automatic onboarding enrollment for accounts created after this migration.
-- Existing accounts are intentionally NOT backfilled or auto-enrolled.

alter table public.docukeep_onboarding_progress
  add column if not exists completed_steps integer[] not null default '{}',
  add column if not exists date_started timestamptz,
  add column if not exists date_completed timestamptz,
  add column if not exists auto_enrolled boolean not null default false;

-- Keep old completed records completed and preserve their completion timestamp.
update public.docukeep_onboarding_progress
set status='completed', date_completed=coalesce(date_completed,completed_at)
where completed_at is not null and status <> 'completed';

create or replace function public.docukeep_enroll_new_user_onboarding()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.docukeep_onboarding_progress
    (user_id,status,current_step,completed_steps,date_started,date_completed,auto_enrolled,updated_at)
  values
    (new.id,'not_started',0,'{}',null,null,true,now())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- The trigger only creates a tutorial record. It does not verify email,
-- approve accounts, create a profile, or grant access to protected features.
drop trigger if exists docukeep_auth_user_onboarding_enroll on auth.users;
create trigger docukeep_auth_user_onboarding_enroll
after insert on auth.users
for each row execute function public.docukeep_enroll_new_user_onboarding();

-- Ensure authenticated users can persist only their own progress (existing RLS policies remain).
grant select, insert, update on public.docukeep_onboarding_progress to authenticated;
