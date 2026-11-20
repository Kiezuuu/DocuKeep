-- DocuKeep public/private document visibility
-- Run this in Supabase SQL Editor after the existing DocuKeep migrations.
-- Public means visible to authenticated DocuKeep users, not anonymous internet visitors.

alter table public.documents
  add column if not exists is_public boolean not null default false;

create index if not exists documents_public_created_idx
  on public.documents(is_public, created_at desc)
  where is_public = true;

-- Users can read their own documents, documents explicitly shared with them,
-- public documents, and staff-visible records. Private documents stay private.
drop policy if exists "read own shared documents or staff" on public.documents;
drop policy if exists "docukeep documents owner public shared staff read" on public.documents;
create policy "docukeep documents owner public shared staff read"
on public.documents for select to authenticated
using (
  owner_id = auth.uid()
  or is_public = true
  or public.is_docukeep_staff()
  or public.docukeep_can_read_document(id, auth.uid())
);

-- Only the owner can change document metadata/visibility through this policy.
drop policy if exists "docukeep document owner updates own metadata" on public.documents;
create policy "docukeep document owner updates own metadata"
on public.documents for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

-- Storage objects remain in the existing PRIVATE bucket. Authenticated users
-- can fetch the file only if its document row is public, owned by them, staff-visible,
-- or explicitly shared through the existing document access rules.
drop policy if exists "docukeep public documents file read" on storage.objects;
create policy "docukeep public documents file read"
on storage.objects for select to authenticated
using (
  bucket_id = 'docukeep-files'
  and exists (
    select 1 from public.documents d
    where d.storage_path = storage.objects.name
      and d.is_public = true
  )
);

comment on column public.documents.is_public is
  'When true, visible to authenticated DocuKeep users. False means private to owner and authorized staff/shares.';
