-- DocuKeep upload P0001 investigation (READ ONLY)
-- Run in Supabase SQL Editor and share the result grids. This does not change schema, RLS, or data.

-- 1) All enabled triggers on document and Storage metadata tables, with their exact functions.
select
  n.nspname as table_schema,
  c.relname as table_name,
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid, true) as trigger_definition,
  pn.nspname as function_schema,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as function_definition
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
join pg_namespace pn on pn.oid = p.pronamespace
where not t.tgisinternal
  and ((n.nspname = 'public' and c.relname = 'documents')
    or (n.nspname = 'storage' and c.relname = 'objects'))
order by n.nspname, c.relname, t.tgname;

-- 2) Public functions whose source explicitly raises exceptions (including P0001 defaults).
select
  n.nspname as function_schema,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'storage')
  and p.prokind = 'f'
  and pg_get_functiondef(p.oid) ilike '%raise exception%'
order by n.nspname, p.proname;

-- 3) Document table columns and constraints (including required fields / size checks).
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'documents'
order by ordinal_position;

select conname, contype, pg_get_constraintdef(oid, true) as constraint_definition
from pg_constraint
where conrelid = 'public.documents'::regclass
order by conname;

-- 4) Active RLS policies on documents and Storage objects.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where (schemaname = 'public' and tablename = 'documents')
   or (schemaname = 'storage' and tablename = 'objects')
order by schemaname, tablename, policyname;

-- 5) Profile role/status distribution. No email or personal data is returned.
select lower(role) as role, lower(status) as status, count(*) as account_count
from public.profiles
group by lower(role), lower(status)
order by lower(role), lower(status);

-- 6) Current private bucket settings and file-size limit.
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'docukeep-files';
