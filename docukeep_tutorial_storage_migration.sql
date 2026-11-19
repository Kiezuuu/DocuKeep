-- DocuKeep Tutorials + per-account storage quotas
-- Run AFTER the existing DocuKeep base, folder, and subscription/payment migrations.
-- Free: 200 MB (200,000,000 bytes). Premium: 20 GB (20,000,000,000 bytes).
-- Uses the existing Supabase Auth, profiles, entitlement table, and private document bucket.

create extension if not exists pgcrypto;

-- Normalize existing entitlements. Premium activation remains controlled by the existing
-- staff-approval/payment workflow; clicking Upgrade never changes an entitlement.
create or replace function public.docukeep_set_storage_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.plan = 'premium' and new.active = true
     and new.expires_at is not null and new.expires_at > now() then
    new.storage_limit_bytes := 20000000000;
  else
    new.storage_limit_bytes := 200000000;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists docukeep_entitlement_storage_limit on public.docukeep_entitlements;
create trigger docukeep_entitlement_storage_limit
before insert or update of plan, active, expires_at, storage_limit_bytes
on public.docukeep_entitlements
for each row execute function public.docukeep_set_storage_limit();

update public.docukeep_entitlements
set storage_limit_bytes = case
  when plan='premium' and active=true and expires_at is not null and expires_at>now()
    then 20000000000 else 200000000 end,
    updated_at=now();

-- New private bucket for tutorial cover images and attachments.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('docukeep-tutorials','docukeep-tutorials',false,20000000000,null)
on conflict (id) do update
set public=false, file_size_limit=20000000000, allowed_mime_types=null;

-- Raise the existing document bucket's per-file ceiling to the account maximum.
-- The account-wide quota below remains authoritative.
update storage.buckets
set file_size_limit=20000000000
where id='docukeep-files';

create table if not exists public.docukeep_tutorials (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 140),
  description text not null check (length(trim(description)) between 1 and 600),
  category text not null check (length(trim(category)) between 1 and 60),
  content text not null check (length(trim(content)) > 0),
  cover_path text,
  status text not null default 'published' check (status in ('draft','published')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.docukeep_tutorial_assets (
  id uuid primary key default gen_random_uuid(),
  tutorial_id uuid not null references public.docukeep_tutorials(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null default 'application/octet-stream',
  size_bytes bigint not null check (size_bytes > 0),
  asset_type text not null default 'attachment' check (asset_type in ('cover','attachment')),
  created_at timestamptz not null default now(),
  constraint docukeep_tutorial_asset_owner_path check (storage_path like owner_id::text || '/%')
);


create or replace function public.docukeep_touch_tutorial_updated_at()
returns trigger language plpgsql set search_path=public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists docukeep_tutorial_updated_at on public.docukeep_tutorials;
create trigger docukeep_tutorial_updated_at
before update on public.docukeep_tutorials
for each row execute function public.docukeep_touch_tutorial_updated_at();

create index if not exists docukeep_tutorials_owner_created_idx
  on public.docukeep_tutorials(owner_id, created_at desc);
create index if not exists docukeep_tutorials_status_created_idx
  on public.docukeep_tutorials(status, created_at desc);
create index if not exists docukeep_tutorial_assets_owner_idx
  on public.docukeep_tutorial_assets(owner_id, created_at desc);

alter table public.docukeep_tutorials enable row level security;
alter table public.docukeep_tutorial_assets enable row level security;

drop policy if exists "tutorials published or own read" on public.docukeep_tutorials;
create policy "tutorials published or own read"
on public.docukeep_tutorials for select to authenticated
using (status='published' or owner_id=auth.uid());

drop policy if exists "tutorials insert own" on public.docukeep_tutorials;
create policy "tutorials insert own"
on public.docukeep_tutorials for insert to authenticated
with check (owner_id=auth.uid());

drop policy if exists "tutorials update own" on public.docukeep_tutorials;
create policy "tutorials update own"
on public.docukeep_tutorials for update to authenticated
using (owner_id=auth.uid()) with check (owner_id=auth.uid());

drop policy if exists "tutorials delete own" on public.docukeep_tutorials;
create policy "tutorials delete own"
on public.docukeep_tutorials for delete to authenticated
using (owner_id=auth.uid());

drop policy if exists "tutorial assets published or own read" on public.docukeep_tutorial_assets;
create policy "tutorial assets published or own read"
on public.docukeep_tutorial_assets for select to authenticated
using (
  owner_id=auth.uid() or exists (
    select 1 from public.docukeep_tutorials t
    where t.id=tutorial_id and t.status='published'
  )
);

drop policy if exists "tutorial assets insert own" on public.docukeep_tutorial_assets;
create policy "tutorial assets insert own"
on public.docukeep_tutorial_assets for insert to authenticated
with check (
  owner_id=auth.uid() and exists (
    select 1 from public.docukeep_tutorials t
    where t.id=tutorial_id and t.owner_id=auth.uid()
  )
);

drop policy if exists "tutorial assets delete own" on public.docukeep_tutorial_assets;
create policy "tutorial assets delete own"
on public.docukeep_tutorial_assets for delete to authenticated
using (owner_id=auth.uid());

-- Validate asset metadata against the actual private Storage object.
create or replace function public.docukeep_validate_tutorial_asset()
returns trigger language plpgsql security definer set search_path=public,storage as $$
declare v_size bigint; v_owner uuid;
begin
  select t.owner_id into v_owner from public.docukeep_tutorials t where t.id=new.tutorial_id;
  if v_owner is null or v_owner <> new.owner_id or new.owner_id <> auth.uid() then
    raise exception 'Tutorial asset owner mismatch.';
  end if;
  select nullif(o.metadata->>'size','')::bigint into v_size
  from storage.objects o
  where o.bucket_id='docukeep-tutorials' and o.name=new.storage_path;
  if v_size is null or v_size <> new.size_bytes then
    raise exception 'Tutorial asset size does not match the uploaded file.';
  end if;
  return new;
end;
$$;
drop trigger if exists docukeep_tutorial_asset_validate on public.docukeep_tutorial_assets;
create trigger docukeep_tutorial_asset_validate
before insert or update of tutorial_id,owner_id,storage_path,size_bytes
on public.docukeep_tutorial_assets
for each row execute function public.docukeep_validate_tutorial_asset();

-- One shared per-user advisory lock prevents simultaneous uploads from racing past quota.
-- Count actual Storage object metadata from BOTH the existing document bucket and tutorial bucket,
-- rather than trusting browser-supplied size values or duplicate metadata rows.
create or replace function public.docukeep_enforce_object_storage_quota()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_owner uuid;
  v_size bigint;
  v_used bigint;
  v_limit bigint;
  v_premium boolean;
begin
  if new.bucket_id not in ('docukeep-files','docukeep-tutorials') then
    return new;
  end if;
  begin
    v_owner := split_part(new.name,'/',1)::uuid;
  exception when others then
    raise exception 'Storage path must begin with your account ID.';
  end;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'You may only upload files into your own account folder.';
  end if;
  if TG_OP='UPDATE' then
    if split_part(old.name,'/',1)::uuid <> auth.uid() then
      raise exception 'You may only modify files in your own account folder.';
    end if;
  end if;
  v_size := nullif(new.metadata->>'size','')::bigint;
  if v_size is null or v_size <= 0 then
    raise exception 'The uploaded file size could not be verified.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_owner::text, 0));

  select (e.plan='premium' and e.active=true and e.expires_at is not null and e.expires_at>now()),
         case when e.plan='premium' and e.active=true and e.expires_at is not null and e.expires_at>now()
              then 20000000000 else 200000000 end
    into v_premium,v_limit
  from public.docukeep_entitlements e where e.user_id=v_owner;
  if not found then v_limit:=200000000; end if;

  select coalesce(sum(nullif(o.metadata->>'size','')::bigint),0)
    into v_used
  from storage.objects o
  where o.bucket_id in ('docukeep-files','docukeep-tutorials')
    and split_part(o.name,'/',1)=v_owner::text
    and not (o.bucket_id=new.bucket_id and o.name=new.name);

  if v_used + v_size > v_limit then
    raise exception 'Storage quota exceeded. Used: % bytes; available: % bytes.', v_used, greatest(v_limit-v_used,0);
  end if;
  return new;
end;
$$;

drop trigger if exists docukeep_storage_object_quota_guard on storage.objects;
create trigger docukeep_storage_object_quota_guard
before insert or update on storage.objects
for each row execute function public.docukeep_enforce_object_storage_quota();

create or replace function public.docukeep_guard_object_delete()
returns trigger language plpgsql security definer set search_path=public,storage as $$
begin
  if old.bucket_id='docukeep-tutorials' then
    if split_part(old.name,'/',1)::uuid <> auth.uid() then
      raise exception 'You may only delete tutorial files in your own account folder.';
    end if;
  elsif old.bucket_id='docukeep-files' then
    if split_part(old.name,'/',1)::uuid <> auth.uid()
       and not public.is_docukeep_staff() then
      raise exception 'You may only delete your own document files.';
    end if;
  end if;
  return old;
end;
$$;
drop trigger if exists docukeep_storage_object_delete_guard on storage.objects;
create trigger docukeep_storage_object_delete_guard
before delete on storage.objects
for each row execute function public.docukeep_guard_object_delete();

-- Private tutorial bucket access: owners manage their files; signed reads are allowed only
-- for assets attached to published tutorials or files owned by the current user.
drop policy if exists "tutorial files upload own" on storage.objects;
create policy "tutorial files upload own" on storage.objects
for insert to authenticated with check (
  bucket_id='docukeep-tutorials' and (storage.foldername(name))[1]=auth.uid()::text
);
drop policy if exists "tutorial files read published or own" on storage.objects;
create policy "tutorial files read published or own" on storage.objects
for select to authenticated using (
  bucket_id='docukeep-tutorials' and (
    (storage.foldername(name))[1]=auth.uid()::text or exists (
      select 1 from public.docukeep_tutorial_assets a
      join public.docukeep_tutorials t on t.id=a.tutorial_id
      where a.storage_path=name and t.status='published'
    )
  )
);
drop policy if exists "tutorial files delete own" on storage.objects;
create policy "tutorial files delete own" on storage.objects
for delete to authenticated using (
  bucket_id='docukeep-tutorials' and (storage.foldername(name))[1]=auth.uid()::text
);

-- The same object-level quota guard covers direct uploads to the existing document bucket.
-- Keep existing document bucket read policies intact; these policies only govern inserts/deletes.
drop policy if exists "docukeep document files upload own folder" on storage.objects;
create policy "docukeep document files upload own folder" on storage.objects
for insert to authenticated with check (
  bucket_id='docukeep-files' and (storage.foldername(name))[1]=auth.uid()::text
);
drop policy if exists "docukeep document files delete own folder" on storage.objects;
drop policy if exists "docukeep document files delete own or staff" on storage.objects;
create policy "docukeep document files delete own or staff" on storage.objects
for delete to authenticated using (
  bucket_id='docukeep-files' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_docukeep_staff())
);

-- Securely return the current account's quota and actual usage to the dashboard.
create or replace function public.docukeep_get_my_storage_usage()
returns table(plan text, used_bytes bigint, limit_bytes bigint)
language plpgsql stable security definer set search_path=public,storage as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Sign in required.'; end if;
  return query
  select case when e.plan='premium' and e.active=true and e.expires_at is not null and e.expires_at>now()
              then 'premium' else 'free' end,
         coalesce((select sum(nullif(o.metadata->>'size','')::bigint)
                   from storage.objects o
                   where o.bucket_id in ('docukeep-files','docukeep-tutorials')
                     and split_part(o.name,'/',1)=v_user::text),0)::bigint,
         case when e.plan='premium' and e.active=true and e.expires_at is not null and e.expires_at>now()
              then 20000000000 else 200000000 end::bigint
  from (select 1) seed
  left join public.docukeep_entitlements e on e.user_id=v_user;
end;
$$;
revoke all on function public.docukeep_get_my_storage_usage() from public,anon;
grant execute on function public.docukeep_get_my_storage_usage() to authenticated;

-- Match the existing premium-check function to the exact active entitlement window.
create or replace function public.docukeep_has_active_premium(p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.docukeep_entitlements e
    where e.user_id=p_user_id and e.plan='premium' and e.active=true
      and e.expires_at is not null and e.expires_at>now()
  );
$$;
revoke all on function public.docukeep_has_active_premium(uuid) from public,anon;
grant execute on function public.docukeep_has_active_premium(uuid) to authenticated;

-- Keep all pre-existing expiry jobs aligned with the new Free quota.
create or replace function public.expire_docukeep_subscriptions()
returns integer language plpgsql security definer set search_path=public as $$
declare n integer;
begin
  update public.docukeep_entitlements
     set active=false, plan='free', storage_limit_bytes=200000000, updated_at=now()
   where plan='premium' and active=true and expires_at is not null and expires_at<=now();
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.expire_docukeep_subscriptions() from public,anon,authenticated;

create or replace function public.expire_docukeep_premium_subscriptions()
returns void language sql security definer set search_path=public as $$
  update public.docukeep_entitlements set plan='free',active=true,
    storage_limit_bytes=200000000,updated_at=now()
  where plan='premium' and expires_at is not null and expires_at<=now();
$$;
revoke all on function public.expire_docukeep_premium_subscriptions() from public,anon,authenticated;

-- Optional: grant the minimum table privileges used by the frontend.
grant select,insert,update,delete on public.docukeep_tutorials to authenticated;
grant select,insert,delete on public.docukeep_tutorial_assets to authenticated;
