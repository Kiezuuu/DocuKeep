-- DocuKeep incremental feature migration (run AFTER the existing setup)
-- Keeps existing profiles, documents, Auth users and private Storage bucket.
create extension if not exists pgcrypto;

-- FIX: Public signup provisions only student/teacher. Other Auth users (including
-- dashboard-created staff users) must not be rejected by this trigger.
create or replace function public.handle_docukeep_signup()
returns trigger language plpgsql security definer set search_path = public, auth as $$
declare requested_role text; mail_domain text;
begin
  requested_role := coalesce(new.raw_user_meta_data->>'requested_role','');
  if requested_role not in ('student','teacher') then return new; end if;
  mail_domain := lower(split_part(coalesce(new.email,''),'@',2));
  if requested_role='student' and mail_domain <> 'gmail.com' then
    raise exception 'Students must register with a personal Gmail address.';
  end if;
  if requested_role='teacher' and mail_domain <> 'deped.gov.ph' then
    raise exception 'Teachers must use their official DepEd email address.';
  end if;
  insert into public.profiles(id,full_name,email,role,department,status)
  values(new.id,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),'New user'),lower(new.email),requested_role,nullif(new.raw_user_meta_data->>'department',''),'pending')
  on conflict (id) do nothing;
  return new;
end; $$;

-- Ensure latest staff identity is provisioned; this does not create an Auth user.
insert into public.profiles(id,full_name,email,role,department,status)
select u.id, coalesce(nullif(u.raw_user_meta_data->>'full_name',''),'DocuKeep Staff'),lower(u.email),'staff','Administration','approved'
from auth.users u where u.id='4e6c5f42-e751-4fa3-ad92-5746d9ee8323'::uuid
on conflict(id) do update set role='staff',status='approved',department='Administration',email=excluded.email;

-- Folder organization. Files remain in the existing private Storage bucket.
create table if not exists public.docukeep_folders (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.profiles(id) on delete cascade,
 name text not null check (length(trim(name)) between 1 and 80),
 color text not null default '#2862a5' check (color ~ '^#[0-9A-Fa-f]{6}$'),
 created_at timestamptz not null default now(),
 unique(owner_id,name)
);

create table if not exists public.docukeep_notifications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null,
 message text not null,
 notification_type text not null default 'general',
 related_document_id uuid references public.documents(id) on delete cascade,
 dedupe_key text unique,
 is_read boolean not null default false,
 created_at timestamptz not null default now()
);

-- Additive document metadata; nullable for backward compatibility.
alter table public.documents add column if not exists folder_id uuid references public.docukeep_folders(id) on delete set null;
alter table public.documents add column if not exists sha256 text;
create index if not exists documents_owner_created_idx on public.documents(owner_id,created_at desc);
create index if not exists documents_due_date_idx on public.documents(due_date) where due_date is not null;
create index if not exists notifications_user_created_idx on public.docukeep_notifications(user_id,created_at desc);

-- Premium entitlement is admin-controlled. No payment provider is assumed.
create table if not exists public.docukeep_entitlements (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 plan text not null default 'free' check(plan in ('free','premium')),
 storage_limit_bytes bigint not null default 26214400 check(storage_limit_bytes > 0),
 active boolean not null default true,
 updated_at timestamptz not null default now()
);
insert into public.docukeep_entitlements(user_id,plan,storage_limit_bytes,active)
select id,'free',26214400,true from public.profiles on conflict(user_id) do nothing;

-- Group access schema. Group sharing must be explicitly granted; private by default.
create table if not exists public.docukeep_groups (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(trim(name)) between 1 and 100),
 created_by uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now()
);
create table if not exists public.docukeep_group_members (
 group_id uuid not null references public.docukeep_groups(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 member_role text not null default 'member' check(member_role in ('owner','member')),
 created_at timestamptz not null default now(),
 primary key(group_id,user_id)
);
create table if not exists public.docukeep_document_access (
 id uuid primary key default gen_random_uuid(),
 document_id uuid not null references public.documents(id) on delete cascade,
 user_id uuid references public.profiles(id) on delete cascade,
 group_id uuid references public.docukeep_groups(id) on delete cascade,
 permission text not null check(permission in ('view','edit')),
 granted_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 check ((user_id is not null)::int + (group_id is not null)::int = 1),
 unique(document_id,user_id,group_id)
);

-- Offline upload records are audit metadata only; actual file blobs stay in browser IndexedDB
-- until uploaded to Supabase Storage.
create table if not exists public.docukeep_upload_sync (
 id uuid primary key,
 owner_id uuid not null references public.profiles(id) on delete cascade,
 storage_path text not null,
 file_name text not null,
 file_size bigint not null check(file_size >= 0),
 state text not null default 'queued' check(state in ('queued','uploading','uploaded','failed')),
 last_error text,
 updated_at timestamptz not null default now()
);

-- All added tables are private. Staff access is based on the existing approved staff helper.
alter table public.docukeep_folders enable row level security;
alter table public.docukeep_notifications enable row level security;
alter table public.docukeep_entitlements enable row level security;
alter table public.docukeep_groups enable row level security;
alter table public.docukeep_group_members enable row level security;
alter table public.docukeep_document_access enable row level security;
alter table public.docukeep_upload_sync enable row level security;

-- SECURITY DEFINER helpers avoid recursive RLS evaluation between group and membership tables.
create or replace function public.docukeep_is_group_member(p_group_id uuid,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.docukeep_group_members m where m.group_id=p_group_id and m.user_id=p_user_id);
$$;
create or replace function public.docukeep_is_group_owner(p_group_id uuid,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.docukeep_groups g where g.id=p_group_id and g.created_by=p_user_id);
$$;
create or replace function public.docukeep_can_read_document(p_document_id uuid,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.documents d where d.id=p_document_id and d.owner_id=p_user_id)
 or exists(select 1 from public.docukeep_document_access a where a.document_id=p_document_id and (a.user_id=p_user_id or (a.group_id is not null and public.docukeep_is_group_member(a.group_id,p_user_id))));
$$;
revoke all on function public.docukeep_is_group_member(uuid,uuid) from public;
revoke all on function public.docukeep_is_group_owner(uuid,uuid) from public;
revoke all on function public.docukeep_can_read_document(uuid,uuid) from public;
grant execute on function public.docukeep_is_group_member(uuid,uuid),public.docukeep_is_group_owner(uuid,uuid),public.docukeep_can_read_document(uuid,uuid) to authenticated;

-- Expand document metadata visibility only for explicitly shared documents.
drop policy if exists "read own documents or staff" on public.documents;
create policy "read own shared documents or staff" on public.documents for select to authenticated
using(owner_id=auth.uid() or public.is_docukeep_staff() or public.docukeep_can_read_document(id,auth.uid()));

-- Folders
 drop policy if exists "folders own or staff read" on public.docukeep_folders;
create policy "folders own or staff read" on public.docukeep_folders for select to authenticated using(owner_id=auth.uid() or public.is_docukeep_staff());
drop policy if exists "folders owner insert" on public.docukeep_folders;
create policy "folders owner insert" on public.docukeep_folders for insert to authenticated with check(owner_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='approved' and p.role in ('student','teacher')));
drop policy if exists "folders owner update" on public.docukeep_folders;
create policy "folders owner update" on public.docukeep_folders for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "folders owner delete" on public.docukeep_folders;
create policy "folders owner delete" on public.docukeep_folders for delete to authenticated using(owner_id=auth.uid() or public.is_docukeep_staff());

-- Notifications: users can only read/update their own notifications; backend functions insert.
drop policy if exists "notifications own read" on public.docukeep_notifications;
create policy "notifications own read" on public.docukeep_notifications for select to authenticated using(user_id=auth.uid() or public.is_docukeep_staff());
drop policy if exists "notifications own update" on public.docukeep_notifications;
create policy "notifications own update" on public.docukeep_notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
revoke insert,delete on public.docukeep_notifications from anon,authenticated;
grant select,update on public.docukeep_notifications to authenticated;

-- Entitlements are visible to their owner; only staff can change them.
drop policy if exists "entitlement own read" on public.docukeep_entitlements;
create policy "entitlement own read" on public.docukeep_entitlements for select to authenticated using(user_id=auth.uid() or public.is_docukeep_staff());
drop policy if exists "entitlement staff manage" on public.docukeep_entitlements;
create policy "entitlement staff manage" on public.docukeep_entitlements for all to authenticated using(public.is_docukeep_staff()) with check(public.is_docukeep_staff());

-- Group and sharing policies: membership required to see group content; owner controls members/shares.
drop policy if exists "group members read" on public.docukeep_groups;
create policy "group members read" on public.docukeep_groups for select to authenticated using(public.is_docukeep_staff() or created_by=auth.uid() or public.docukeep_is_group_member(id,auth.uid()));
drop policy if exists "group owner create" on public.docukeep_groups;
create policy "group owner create" on public.docukeep_groups for insert to authenticated with check(created_by=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='approved'));
drop policy if exists "group owner update" on public.docukeep_groups;
create policy "group owner update" on public.docukeep_groups for update to authenticated using(created_by=auth.uid() or public.is_docukeep_staff()) with check(created_by=auth.uid() or public.is_docukeep_staff());
drop policy if exists "members own read" on public.docukeep_group_members;
create policy "members own read" on public.docukeep_group_members for select to authenticated using(user_id=auth.uid() or public.docukeep_is_group_owner(group_id,auth.uid()) or public.is_docukeep_staff());
drop policy if exists "group creator manages members" on public.docukeep_group_members;
create policy "group creator manages members" on public.docukeep_group_members for all to authenticated using(public.docukeep_is_group_owner(group_id,auth.uid()) or public.is_docukeep_staff()) with check(public.docukeep_is_group_owner(group_id,auth.uid()) or public.is_docukeep_staff());
drop policy if exists "document access read" on public.docukeep_document_access;
create policy "document access read" on public.docukeep_document_access for select to authenticated using(public.docukeep_can_read_document(document_id,auth.uid()) or public.is_docukeep_staff());
drop policy if exists "document owner manages access" on public.docukeep_document_access;
create policy "document owner manages access" on public.docukeep_document_access for all to authenticated using(exists(select 1 from public.documents d where d.id=document_id and d.owner_id=auth.uid()) or public.is_docukeep_staff()) with check(exists(select 1 from public.documents d where d.id=document_id and d.owner_id=auth.uid()) or public.is_docukeep_staff());

-- Sync metadata belongs to its owner; browser IndexedDB remains the source for offline blobs.
drop policy if exists "upload sync own all" on public.docukeep_upload_sync;
create policy "upload sync own all" on public.docukeep_upload_sync for all to authenticated using(owner_id=auth.uid() or public.is_docukeep_staff()) with check(owner_id=auth.uid() or public.is_docukeep_staff());

-- Add authorized shared-file read to Storage SELECT. This grants signed URL access only
-- when the matching document has an explicit user or group grant.
drop policy if exists "shared documents read" on storage.objects;
create policy "shared documents read" on storage.objects for select to authenticated using(
 bucket_id='docukeep-files' and exists(
  select 1 from public.documents d join public.docukeep_document_access a on a.document_id=d.id
  where d.storage_path=name and (a.user_id=auth.uid() or (a.group_id is not null and public.docukeep_is_group_member(a.group_id,auth.uid())))
 )
);

-- Cron target: schedule this function daily using Supabase Cron (SQL Editor > Cron).
-- Idempotent keys prevent duplicate reminders across repeated runs.
create or replace function public.generate_docukeep_deadline_notifications()
returns integer language plpgsql security definer set search_path=public as $$
declare inserted_count integer;
begin
 insert into public.docukeep_notifications(user_id,title,message,notification_type,related_document_id,dedupe_key)
 select d.owner_id,
        case when d.due_date=current_date+1 then 'Deadline tomorrow' when d.due_date=current_date+3 then 'Deadline in 3 days' else 'Deadline in 7 days' end,
        format('%s is due on %s.',d.title,to_char(d.due_date,'Mon DD, YYYY')),
        'deadline',d.id,'deadline:'||d.id::text||':'||d.due_date::text||':'||(d.due_date-current_date)::text
 from public.documents d
 join public.profiles p on p.id=d.owner_id and p.status='approved'
 where d.due_date in (current_date+1,current_date+3,current_date+7)
   and d.status not in ('approved','rejected')
 on conflict(dedupe_key) do nothing;
 get diagnostics inserted_count=row_count;
 return inserted_count;
end; $$;
revoke all on function public.generate_docukeep_deadline_notifications() from public,anon,authenticated;

-- Restrict access to private file bucket and keep the existing 25 MB per-file limit.
update storage.buckets set public=false,file_size_limit=26214400 where id='docukeep-files';

-- IMPORTANT: The HTML upload queue uses a stable document UUID as the Storage path
-- and documents.id, so retries do not intentionally create a second document row.
-- DocuKeep User Role Management
-- Run this once in Supabase SQL Editor after the existing DocuKeep setup/migration.
-- It enables approved staff to change other users' roles from the website.

create or replace function public.manage_docukeep_user_role(
  p_user_id uuid,
  p_new_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_email text;
  target_role text;
  approved_staff_count integer;
begin
  if not public.is_docukeep_staff() then
    raise exception 'Staff access required.';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'You cannot change your own role.';
  end if;

  if p_new_role not in ('student', 'teacher', 'staff') then
    raise exception 'Invalid role. Choose student, teacher, or staff.';
  end if;

  select lower(email), role
    into target_email, target_role
  from public.profiles
  where id = p_user_id;

  if not found then
    raise exception 'User profile was not found.';
  end if;

  if p_new_role = 'student' and split_part(target_email, '@', 2) <> 'gmail.com' then
    raise exception 'Student accounts must use a personal Gmail address.';
  end if;

  if p_new_role = 'teacher' and split_part(target_email, '@', 2) <> 'deped.gov.ph' then
    raise exception 'Teacher accounts must use an official @deped.gov.ph address.';
  end if;

  if target_role = 'staff' and p_new_role <> 'staff' then
    select count(*) into approved_staff_count
    from public.profiles
    where role = 'staff' and status = 'approved';

    if approved_staff_count <= 1 then
      raise exception 'You cannot remove the last approved staff administrator.';
    end if;
  end if;

  update public.profiles
  set role = p_new_role,
      status = case when p_new_role = 'staff' then 'approved' else status end
  where id = p_user_id;
end;
$$;

revoke all on function public.manage_docukeep_user_role(uuid, text) from public;
grant execute on function public.manage_docukeep_user_role(uuid, text) to authenticated;

notify pgrst, 'reload schema';
