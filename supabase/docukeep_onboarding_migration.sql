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
