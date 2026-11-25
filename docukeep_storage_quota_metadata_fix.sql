-- DocuKeep Storage quota metadata timing fix
-- Apply in Supabase SQL Editor to an existing project.
-- Keeps the existing trigger, account ownership checks, advisory lock and quotas.
-- Supabase Storage may insert an authorization/probe row before final size metadata
-- is available, then update the row with completed object metadata. The quota check
-- therefore runs when size/contentLength metadata is available instead of rejecting
-- the initial metadata-less insert.

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
  v_metadata_size text;
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

  if TG_OP = 'UPDATE' then
    if split_part(old.name,'/',1)::uuid <> auth.uid() then
      raise exception 'You may only modify files in your own account folder.';
    end if;
  end if;

  -- Supabase Storage first creates an authorization/probe row before the
  -- object upload has completed. That initial row can have no final `size`
  -- metadata yet. The Storage service writes the completed metadata in a
  -- subsequent UPDATE. Enforce quota when a trustworthy size is available;
  -- do not reject the initial metadata-less insert.
  v_metadata_size := coalesce(
    nullif(new.metadata->>'size',''),
    nullif(new.metadata->>'contentLength',''),
    case when TG_OP = 'UPDATE' then nullif(old.metadata->>'size','') end
  );

  if v_metadata_size is null then
    return new;
  end if;

  begin
    v_size := v_metadata_size::bigint;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'The uploaded file size metadata is invalid.';
  end;

  if v_size <= 0 then
    raise exception 'The uploaded file size could not be verified.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_owner::text, 0));

  select case
           when e.plan = 'premium'
            and e.active is true
            and e.expires_at is not null
            and e.expires_at > now()
           then 20000000000
           else 200000000
         end
    into v_limit
  from public.docukeep_entitlements e
  where e.user_id = v_owner;

  if not found then
    v_limit := 200000000;
  end if;

  select coalesce(sum(nullif(o.metadata->>'size','')::bigint), 0)
    into v_used
  from storage.objects o
  where o.bucket_id in ('docukeep-files','docukeep-tutorials')
    and split_part(o.name,'/',1) = v_owner::text
    and not (o.bucket_id = new.bucket_id and o.name = new.name);

  if v_used + v_size > v_limit then
    raise exception 'Storage quota exceeded. Used: % bytes; available: % bytes.',
      v_used, greatest(v_limit - v_used, 0);
  end if;

  return new;
end;
$$;
