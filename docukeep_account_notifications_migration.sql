-- DocuKeep account approval, activity, and push-notification upgrade
-- Run AFTER the existing DocuKeep core, role-management, storage, and onboarding migrations.
-- Back up the Supabase project before applying. This is additive except for the signup trigger function.

create extension if not exists pgcrypto;

-- Personal Gmail registration for both student and teacher public signups.
-- Staff accounts must continue to be provisioned only by authorized staff.
create or replace function public.handle_docukeep_signup()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare requested_role text; mail_domain text;
begin
  requested_role := lower(coalesce(new.raw_user_meta_data->>'requested_role',''));
  if requested_role not in ('student','teacher') then return new; end if;
  mail_domain := lower(split_part(coalesce(new.email,''),'@',2));
  if mail_domain <> 'gmail.com' then
    raise exception 'Students and teachers must register with a personal Gmail address.';
  end if;
  insert into public.profiles(id,full_name,email,role,department,status)
  values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),'New user'),lower(new.email),requested_role,nullif(trim(new.raw_user_meta_data->>'department'),''),'pending')
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Append-only audit/activity history. Read state is maintained independently for user-facing activity.
create table if not exists public.docukeep_activity_log (
  id uuid primary key default gen_random_uuid(),
  activity_type text not null,
  description text not null,
  actor_user_id uuid references public.profiles(id) on delete set null,
  related_user_id uuid references public.profiles(id) on delete cascade,
  related_document_id uuid references public.documents(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists docukeep_activity_related_user_idx on public.docukeep_activity_log(related_user_id,created_at desc);
create index if not exists docukeep_activity_created_idx on public.docukeep_activity_log(created_at desc);
alter table public.docukeep_activity_log enable row level security;
drop policy if exists "activity own or staff read" on public.docukeep_activity_log;
create policy "activity own or staff read" on public.docukeep_activity_log for select to authenticated using (related_user_id=auth.uid() or public.is_docukeep_staff());
drop policy if exists "activity own read update" on public.docukeep_activity_log;
create policy "activity own read update" on public.docukeep_activity_log for update to authenticated using (related_user_id=auth.uid()) with check (related_user_id=auth.uid());
revoke insert,delete on public.docukeep_activity_log from anon,authenticated;
grant select,update on public.docukeep_activity_log to authenticated;

-- Browser push endpoints are private to their owning account. The Edge Function uses service-role access.
create table if not exists public.docukeep_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists docukeep_push_subscriptions_user_idx on public.docukeep_push_subscriptions(user_id);
alter table public.docukeep_push_subscriptions enable row level security;
drop policy if exists "push subscriptions own select" on public.docukeep_push_subscriptions;
create policy "push subscriptions own select" on public.docukeep_push_subscriptions for select to authenticated using(user_id=auth.uid());
drop policy if exists "push subscriptions own insert" on public.docukeep_push_subscriptions;
create policy "push subscriptions own insert" on public.docukeep_push_subscriptions for insert to authenticated with check(user_id=auth.uid());
drop policy if exists "push subscriptions own update" on public.docukeep_push_subscriptions;
create policy "push subscriptions own update" on public.docukeep_push_subscriptions for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "push subscriptions own delete" on public.docukeep_push_subscriptions;
create policy "push subscriptions own delete" on public.docukeep_push_subscriptions for delete to authenticated using(user_id=auth.uid());
grant select,insert,update,delete on public.docukeep_push_subscriptions to authenticated;

-- One central notification insert helper: persistent in-app notification + activity record.
create or replace function public.docukeep_emit_notification(
  p_user_id uuid, p_title text, p_message text, p_type text,
  p_document_id uuid default null, p_dedupe_key text default null,
  p_actor_id uuid default null, p_metadata jsonb default '{}'::jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare inserted_id uuid;
begin
  if p_user_id is null then return; end if;
  insert into public.docukeep_notifications(user_id,title,message,notification_type,related_document_id,dedupe_key,is_read)
  values(p_user_id,p_title,p_message,p_type,p_document_id,p_dedupe_key,false)
  on conflict (dedupe_key) do nothing
  returning id into inserted_id;
  if inserted_id is not null then
    insert into public.docukeep_activity_log(activity_type,description,actor_user_id,related_user_id,related_document_id,metadata)
    values(p_type,p_message,p_actor_id,p_user_id,p_document_id,coalesce(p_metadata,'{}'::jsonb));
  end if;
end;
$$;
revoke all on function public.docukeep_emit_notification(uuid,text,text,text,uuid,text,uuid,jsonb) from public,anon,authenticated;

-- Secure account approval/rejection. Client cannot set roles or approve itself.
create or replace function public.docukeep_review_profile(p_user_id uuid,p_status text,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare target public.profiles%rowtype; actor uuid := auth.uid();
begin
  if not public.is_docukeep_staff() then raise exception 'Staff access required.'; end if;
  if p_user_id is null or p_user_id=actor then raise exception 'You cannot approve or reject your own account.'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Invalid account decision.'; end if;
  if p_status='rejected' and length(trim(coalesce(p_reason,'')))=0 then raise exception 'A rejection reason is required.'; end if;
  select * into target from public.profiles where id=p_user_id for update;
  if not found then raise exception 'Account not found.'; end if;
  if target.role not in ('student','teacher') then raise exception 'Only student or teacher registrations can be reviewed here.'; end if;
  if target.status=p_status then return; end if;
  update public.profiles set status=p_status where id=p_user_id;
  perform public.docukeep_emit_notification(p_user_id,
    case when p_status='approved' then 'Your account has been approved!' else 'Your account registration was rejected.' end,
    case when p_status='approved' then 'Your DocuKeep account is now approved. You can sign in.' else 'Reason: '||trim(p_reason) end,
    'account_'||p_status,null,'account-review:'||p_user_id::text||':'||p_status,actor,
    jsonb_build_object('status',p_status,'reviewed_by',actor));
  insert into public.docukeep_activity_log(activity_type,description,actor_user_id,related_user_id,metadata)
  values('account_'||p_status,'Account '||p_status||' by authorized staff.',actor,p_user_id,jsonb_build_object('reason',p_reason));
end;
$$;
revoke all on function public.docukeep_review_profile(uuid,text,text) from public,anon;
grant execute on function public.docukeep_review_profile(uuid,text,text) to authenticated;

-- Secure document review. This replaces the previous direct browser-side UPDATE.
create or replace function public.docukeep_review_document(p_document_id uuid,p_status text,p_comment text default null)
returns void language plpgsql security definer set search_path=public as $$
declare target public.documents%rowtype; actor uuid := auth.uid();
begin
  if not public.is_docukeep_staff() then raise exception 'Staff access required.'; end if;
  if p_status not in ('approved','needs_revision','rejected') then raise exception 'Invalid document status.'; end if;
  if p_status in ('needs_revision','rejected') and length(trim(coalesce(p_comment,'')))=0 then raise exception 'A review comment is required.'; end if;
  select * into target from public.documents where id=p_document_id for update;
  if not found then raise exception 'Document not found.'; end if;
  if target.status=p_status and coalesce(target.review_comment,'')=coalesce(nullif(trim(p_comment),''),'') then return; end if;
  update public.documents set status=p_status,review_comment=nullif(trim(p_comment),''),reviewed_at=now(),reviewed_by=actor where id=p_document_id;
  perform public.docukeep_emit_notification(target.owner_id,
    case p_status when 'approved' then 'Your file has been accepted!' when 'needs_revision' then 'Your file requires some corrections.' else 'Your file has been rejected.' end,
    case p_status when 'approved' then 'Your document '||coalesce(target.file_name,target.title)||' has been accepted.' when 'needs_revision' then 'Please review the requested corrections: '||trim(p_comment) else 'Review feedback: '||trim(p_comment) end,
    'document_'||p_status,p_document_id,'document-review:'||p_document_id::text||':'||p_status,actor,
    jsonb_build_object('status',p_status,'file_name',target.file_name));
end;
$$;
revoke all on function public.docukeep_review_document(uuid,text,text) from public,anon;
grant execute on function public.docukeep_review_document(uuid,text,text) to authenticated;

-- Log new registrations and new uploads without granting clients insert privileges on the audit table.
create or replace function public.docukeep_log_profile_registration()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.docukeep_activity_log(activity_type,description,related_user_id,metadata)
    values('account_registration','New '||new.role||' account registration submitted.',new.id,jsonb_build_object('email',new.email,'status',new.status));
    perform public.docukeep_emit_notification(new.id,'Your account registration is pending.','Your registration was received and is waiting for administrator or authorized staff approval.','account_pending',null,'account-pending:'||new.id::text,null,jsonb_build_object('status','pending'));
  elsif old.status is distinct from new.status and new.status in ('approved','rejected') then
    insert into public.docukeep_activity_log(activity_type,description,related_user_id,metadata)
    values('account_status','Account status changed to '||new.status||'.',new.id,jsonb_build_object('previous_status',old.status,'status',new.status));
  end if;
  return new;
end; $$;
drop trigger if exists docukeep_profile_activity_trigger on public.profiles;
create trigger docukeep_profile_activity_trigger after insert or update of status on public.profiles for each row execute function public.docukeep_log_profile_registration();

create or replace function public.docukeep_log_document_upload()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  perform public.docukeep_emit_notification(new.owner_id,'File uploaded successfully','Your document '||coalesce(new.file_name,new.title,'')||' was uploaded and is now in your DocuKeep library.','file_upload',new.id,'file-upload:'||new.id::text,new.owner_id,jsonb_build_object('status',new.status));
  return new;
end; $$;
drop trigger if exists docukeep_document_upload_activity_trigger on public.documents;
create trigger docukeep_document_upload_activity_trigger after insert on public.documents for each row execute function public.docukeep_log_document_upload();

-- Keep realtime notification subscriptions available to authenticated clients.
alter table public.docukeep_notifications replica identity full;
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='docukeep_notifications') then
    alter publication supabase_realtime add table public.docukeep_notifications;
  end if;
exception when undefined_object then null; end $$;

notify pgrst,'reload schema';

-- Keep staff role management aligned with the new personal-Gmail teacher policy.
create or replace function public.manage_docukeep_user_role(p_user_id uuid,p_new_role text)
returns void language plpgsql security definer set search_path=public as $$
declare target_email text; target_role text; approved_staff_count integer;
begin
  if not public.is_docukeep_staff() then raise exception 'Staff access required.'; end if;
  if p_user_id=auth.uid() then raise exception 'You cannot change your own role.'; end if;
  if p_new_role not in ('student','teacher','staff') then raise exception 'Invalid role. Choose student, teacher, or staff.'; end if;
  select lower(email),role into target_email,target_role from public.profiles where id=p_user_id;
  if not found then raise exception 'User profile was not found.'; end if;
  if p_new_role in ('student','teacher') and split_part(target_email,'@',2)<>'gmail.com' then raise exception 'Student and teacher accounts must use a personal Gmail address.'; end if;
  if target_role='staff' and p_new_role<>'staff' then
    select count(*) into approved_staff_count from public.profiles where role='staff' and status='approved';
    if approved_staff_count<=1 then raise exception 'You cannot remove the last approved staff administrator.'; end if;
  end if;
  update public.profiles set role=p_new_role,status=case when p_new_role='staff' then 'approved' else status end where id=p_user_id;
end; $$;
revoke all on function public.manage_docukeep_user_role(uuid,text) from public,anon;
grant execute on function public.manage_docukeep_user_role(uuid,text) to authenticated;

-- Restrict user updates to notification read state only.
revoke update on public.docukeep_notifications from authenticated;
grant update(is_read) on public.docukeep_notifications to authenticated;
revoke update on public.docukeep_activity_log from authenticated;
grant update(is_read) on public.docukeep_activity_log to authenticated;

notify pgrst,'reload schema';
