-- DocuKeep: approved-user document upload permissions
-- Apply this additive migration in the EXISTING Supabase project.
-- It preserves the private bucket and restricts uploads to the signed-in user's own path.

begin;

-- Teacher uploads were missing a clear owner INSERT policy in the supplied
-- incremental migrations. This policy explicitly permits approved DocuKeep roles.
drop policy if exists "docukeep approved owners insert documents" on public.documents;
create policy "docukeep approved owners insert documents"
on public.documents
for insert
to authenticated
with check (
  owner_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.status = 'approved'
      and p.role in ('student', 'teacher', 'staff')
  )
);

-- Keep the document bucket private. A user may create objects only below
-- their own UUID folder: <auth.uid()>/<document-uuid>/<filename>.
drop policy if exists "docukeep approved owners upload own files" on storage.objects;
create policy "docukeep approved owners upload own files"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'docukeep-files'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.status = 'approved'
      and p.role in ('student', 'teacher', 'staff')
  )
);

grant insert on public.documents to authenticated;
grant insert on storage.objects to authenticated;

commit;

-- IMPORTANT:
-- Keep the existing 25 MB per-file bucket limit and quota guard in place.
-- Do not make docukeep-files public. Do not place a service_role key in index.html.
