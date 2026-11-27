-- DocuKeep first-time onboarding completion
create table if not exists public.docukeep_onboarding_progress (
 user_id uuid primary key references auth.users(id) on delete cascade,
 completed_at timestamptz,
 updated_at timestamptz not null default now()
);
alter table public.docukeep_onboarding_progress enable row level security;
drop policy if exists "Users can read own onboarding progress" on public.docukeep_onboarding_progress;
create policy "Users can read own onboarding progress" on public.docukeep_onboarding_progress for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can create own onboarding progress" on public.docukeep_onboarding_progress;
create policy "Users can create own onboarding progress" on public.docukeep_onboarding_progress for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can update own onboarding progress" on public.docukeep_onboarding_progress;
create policy "Users can update own onboarding progress" on public.docukeep_onboarding_progress for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update on public.docukeep_onboarding_progress to authenticated;


-- Backward-compatible tutorial state: skipped/in-progress remain resumable.
alter table public.docukeep_onboarding_progress
 add column if not exists status text not null default 'not_started'
   check (status in ('not_started','in_progress','skipped','completed')),
 add column if not exists current_step integer not null default 0 check (current_step >= 0),
 add column if not exists skipped_at timestamptz;

-- Preserve already-completed users from the earlier one-column implementation.
update public.docukeep_onboarding_progress
 set status='completed'
 where completed_at is not null and status <> 'completed';
