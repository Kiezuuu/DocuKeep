-- DocuKeep Premium subscription requests and manual payment verification
-- Run AFTER docukeep_migration.sql in Supabase SQL Editor.
-- No payment gateway is connected: staff manually verifies each uploaded receipt.

create extension if not exists pgcrypto;

-- Extend the existing entitlement record. Keep profiles.role as student/teacher/staff.
alter table public.docukeep_entitlements
  add column if not exists plan_period text,
  add column if not exists starts_at timestamptz,
  add column if not exists expires_at timestamptz;

-- A request is created by the user and can only be decided by approved staff.
create table if not exists public.docukeep_subscription_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  plan_key text not null check (plan_key in ('weekly','monthly','yearly')),
  amount_php integer not null check (amount_php in (39,99,999)),
  payment_reference text,
  receipt_path text not null,
  user_message text,
  status text not null default 'pending' check (status in ('pending','needs_info','approved','rejected')),
  admin_message text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists docukeep_subscription_user_created_idx
  on public.docukeep_subscription_requests(user_id, created_at desc);
create index if not exists docukeep_subscription_status_created_idx
  on public.docukeep_subscription_requests(status, created_at desc);

alter table public.docukeep_subscription_requests enable row level security;

-- Requests are visible only to their owner and staff. Users cannot update decisions.
drop policy if exists "subscription requests read own or staff" on public.docukeep_subscription_requests;
create policy "subscription requests read own or staff"
  on public.docukeep_subscription_requests for select to authenticated
  using (user_id = auth.uid() or public.is_docukeep_staff());

drop policy if exists "subscription requests insert own" on public.docukeep_subscription_requests;
create policy "subscription requests insert own"
  on public.docukeep_subscription_requests for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.status = 'approved' and p.role in ('student','teacher')
    )
    and status = 'pending'
    and reviewed_by is null and reviewed_at is null
    and starts_at is null and expires_at is null and admin_message is null
  );

revoke all on public.docukeep_subscription_requests from anon;
revoke update, delete on public.docukeep_subscription_requests from anon, authenticated;
grant select, insert on public.docukeep_subscription_requests to authenticated;

-- Private receipt bucket; receipt object paths must start with the submitting user's UUID.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('docukeep-payment-receipts','docukeep-payment-receipts',false,5242880,array['image/jpeg','image/png','application/pdf'])
on conflict (id) do update set public=false,file_size_limit=5242880,
  allowed_mime_types=array['image/jpeg','image/png','application/pdf'];

drop policy if exists "payment receipt owner upload" on storage.objects;
create policy "payment receipt owner upload" on storage.objects
for insert to authenticated with check (
  bucket_id = 'docukeep-payment-receipts'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "payment receipt owner or staff read" on storage.objects;
create policy "payment receipt owner or staff read" on storage.objects
for select to authenticated using (
  bucket_id = 'docukeep-payment-receipts'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_docukeep_staff()
  )
);

-- Prevent users from inserting mismatched prices/plan combinations.
create or replace function public.validate_docukeep_subscription_request()
returns trigger language plpgsql security definer set search_path = public as $$
declare expected_amount integer;
begin
  expected_amount := case new.plan_key when 'weekly' then 39 when 'monthly' then 99 when 'yearly' then 999 else null end;
  if expected_amount is null or new.amount_php <> expected_amount then
    raise exception 'Invalid subscription plan price.';
  end if;
  if new.receipt_path !~ ('^' || new.user_id::text || '/[0-9a-fA-F-]+\.(jpg|png|pdf)$') then
    raise exception 'Invalid payment receipt path.';
  end if;
  return new;
end; $$;
drop trigger if exists docukeep_validate_subscription_request on public.docukeep_subscription_requests;
create trigger docukeep_validate_subscription_request
before insert on public.docukeep_subscription_requests
for each row execute function public.validate_docukeep_subscription_request();

-- Admin accepts/rejects a request. Premium dates are calculated by the database.
create or replace function public.review_docukeep_subscription_request(
  p_request_id uuid,
  p_status text,
  p_admin_message text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare r public.docukeep_subscription_requests%rowtype;
        period_end timestamptz;
begin
  if not public.is_docukeep_staff() then raise exception 'Staff access required.'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Invalid decision.'; end if;
  select * into r from public.docukeep_subscription_requests where id=p_request_id for update;
  if not found then raise exception 'Subscription request not found.'; end if;
  if r.status = 'approved' then raise exception 'This request has already been approved.'; end if;
  if r.status = 'rejected' then raise exception 'This request has already been rejected.'; end if;

  if p_status='approved' then
    period_end := case r.plan_key
      when 'weekly' then now() + interval '7 days'
      when 'monthly' then now() + interval '1 month'
      when 'yearly' then now() + interval '1 year'
    end;
    update public.docukeep_subscription_requests
      set status='approved', admin_message=nullif(trim(p_admin_message),''),
          reviewed_by=auth.uid(), reviewed_at=now(), starts_at=now(), expires_at=period_end, updated_at=now()
      where id=p_request_id;
    insert into public.docukeep_entitlements(user_id,plan,storage_limit_bytes,active,updated_at,plan_period,starts_at,expires_at)
      values(r.user_id,'premium',137438953472,true,now(),r.plan_key,now(),period_end)
    on conflict(user_id) do update set plan='premium',storage_limit_bytes=137438953472,
      active=true,updated_at=now(),plan_period=excluded.plan_period,
      starts_at=excluded.starts_at,expires_at=excluded.expires_at;
  else
    update public.docukeep_subscription_requests
      set status='rejected', admin_message=coalesce(nullif(trim(p_admin_message),''),'Payment could not be verified.'),
          reviewed_by=auth.uid(), reviewed_at=now(), updated_at=now()
      where id=p_request_id;
  end if;
end; $$;

-- Send a transaction message without changing the user's payment decision.
create or replace function public.message_docukeep_subscription_request(
  p_request_id uuid,
  p_admin_message text
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_docukeep_staff() then raise exception 'Staff access required.'; end if;
  if nullif(trim(p_admin_message),'') is null then raise exception 'Message cannot be empty.'; end if;
  update public.docukeep_subscription_requests
    set admin_message=trim(p_admin_message),
        status=case when status='pending' then 'needs_info' else status end,
        reviewed_by=auth.uid(), reviewed_at=now(), updated_at=now()
    where id=p_request_id and status <> 'approved';
  if not found then raise exception 'Request not found or already approved.'; end if;
end; $$;

revoke all on function public.review_docukeep_subscription_request(uuid,text,text) from public, anon;
revoke all on function public.message_docukeep_subscription_request(uuid,text) from public, anon;
grant execute on function public.review_docukeep_subscription_request(uuid,text,text) to authenticated;
grant execute on function public.message_docukeep_subscription_request(uuid,text) to authenticated;

-- Effective Premium status always checks expiry, even if no scheduled cleanup runs.
create or replace function public.docukeep_has_active_premium(p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.docukeep_entitlements e
    where e.user_id=p_user_id and e.plan='premium' and e.active=true
      and e.expires_at is not null and e.expires_at > now()
  );
$$;
revoke all on function public.docukeep_has_active_premium(uuid) from public, anon;
grant execute on function public.docukeep_has_active_premium(uuid) to authenticated;

-- Disable expired entitlements on demand; the active-premium helper already denies them.
create or replace function public.expire_docukeep_premium_subscriptions()
returns integer language plpgsql security definer set search_path=public as $$
declare n integer;
begin
  update public.docukeep_entitlements set active=false,plan='free',storage_limit_bytes=26214400,updated_at=now()
   where plan='premium' and active=true and expires_at is not null and expires_at <= now();
  get diagnostics n=row_count;
  return n;
end; $$;
revoke all on function public.expire_docukeep_premium_subscriptions() from public, anon, authenticated;

notify pgrst, 'reload schema';
