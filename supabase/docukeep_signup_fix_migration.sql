-- DocuKeep signup fix: students AND teachers use personal Gmail addresses.
-- Run this in Supabase SQL Editor. It updates the existing trigger function;
-- it does not delete users, profiles, or existing data.
create or replace function public.handle_docukeep_signup()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  requested_role text;
  mail_domain text;
begin
  requested_role := lower(coalesce(new.raw_user_meta_data->>'requested_role', ''));

  -- Leave staff/admin/service-created Auth users untouched.
  if requested_role not in ('student', 'teacher') then
    return new;
  end if;

  mail_domain := lower(split_part(coalesce(new.email, ''), '@', 2));

  if mail_domain <> 'gmail.com' then
    raise exception 'Students and teachers must register with a personal Gmail address.';
  end if;

  insert into public.profiles
    (id, full_name, email, role, department, status)
  values
    (
      new.id,
      coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), 'New user'),
      lower(new.email),
      requested_role,
      nullif(trim(new.raw_user_meta_data->>'department'), ''),
      'pending'
    )
  on conflict (id) do nothing;

  return new;
end;
$$;

-- Diagnostic query: confirm which Auth triggers call signup functions.
-- Run separately if signup still reports "Database error saving new user":
-- select t.tgname, p.proname
-- from pg_trigger t
-- join pg_class c on c.oid = t.tgrelid
-- join pg_namespace n on n.oid = c.relnamespace
-- join pg_proc p on p.oid = t.tgfoid
-- where n.nspname = 'auth' and c.relname = 'users' and not t.tgisinternal;
