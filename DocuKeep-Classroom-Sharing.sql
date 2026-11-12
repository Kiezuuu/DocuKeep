-- DocuKeep: classroom groups, invitation codes/links, and folder sharing
-- Additive migration. Review the notes before running in Supabase SQL Editor.
-- This migration does NOT make every user's private files public.

begin;

-- 1) Folder-level access grants (one user OR one group per grant).
create table if not exists public.docukeep_folder_access (
    id uuid primary key default gen_random_uuid(),
    folder_id uuid not null references public.docukeep_folders(id) on delete cascade,
    user_id uuid references public.profiles(id) on delete cascade,
    group_id uuid references public.docukeep_groups(id) on delete cascade,
    permission text not null default 'view',
    granted_by uuid not null references public.profiles(id),
    created_at timestamptz not null default now(),
    constraint docukeep_folder_access_one_target
        check ((user_id is not null and group_id is null) or
               (user_id is null and group_id is not null))
);
create index if not exists docukeep_folder_access_folder_idx
    on public.docukeep_folder_access(folder_id);
create index if not exists docukeep_folder_access_user_idx
    on public.docukeep_folder_access(user_id) where user_id is not null;
create index if not exists docukeep_folder_access_group_idx
    on public.docukeep_folder_access(group_id) where group_id is not null;
create unique index if not exists docukeep_folder_access_user_unique
    on public.docukeep_folder_access(folder_id, user_id) where user_id is not null;
create unique index if not exists docukeep_folder_access_group_unique
    on public.docukeep_folder_access(folder_id, group_id) where group_id is not null;

-- 2) Private invitation records. Raw code/token are only returned once by the
-- create function; direct table access is not granted to authenticated users.
create table if not exists public.docukeep_group_invites (
    id uuid primary key default gen_random_uuid(),
    group_id uuid not null references public.docukeep_groups(id) on delete cascade,
    invite_code text not null unique,
    invite_token text not null unique,
    created_by uuid not null references public.profiles(id),
    created_at timestamptz not null default now(),
    expires_at timestamptz,
    disabled_at timestamptz
);
create index if not exists docukeep_group_invites_group_idx
    on public.docukeep_group_invites(group_id, created_at desc);

alter table public.docukeep_folder_access enable row level security;
alter table public.docukeep_group_invites enable row level security;
grant select, insert, update, delete on public.docukeep_folder_access to authenticated;

-- 3) Access helpers. Folder access inherits down the folder tree.
create or replace function public.docukeep_can_read_folder(
    p_folder_id uuid,
    p_user_id uuid default auth.uid()
) returns boolean
language sql stable security definer
set search_path = public
as $$
    with recursive folder_chain(id, parent_id, visited) as (
        select f.id, f.parent_id, array[f.id]::uuid[]
        from public.docukeep_folders f
        where f.id = p_folder_id
        union all
        select parent.id, parent.parent_id, child.visited || parent.id
        from public.docukeep_folders parent
        join folder_chain child on child.parent_id = parent.id
        where not parent.id = any(child.visited)
    )
    select
        (p_user_id = auth.uid() or public.is_docukeep_staff())
        and (
        exists (
            select 1 from public.docukeep_folders f
            where f.id = p_folder_id and f.owner_id = p_user_id
        )
        or public.is_docukeep_staff()
        or exists (
            select 1
            from folder_chain chain
            join public.docukeep_folder_access a on a.folder_id = chain.id
            where a.user_id = p_user_id
               or (a.group_id is not null
                   and public.docukeep_is_group_member(a.group_id, p_user_id))
        )
        );
$$;

create or replace function public.docukeep_can_read_document(
    p_document_id uuid,
    p_user_id uuid default auth.uid()
) returns boolean
language sql stable security definer
set search_path = public
as $$
    select
        (p_user_id = auth.uid() or public.is_docukeep_staff())
        and (
        exists (
            select 1 from public.documents d
            where d.id = p_document_id and d.owner_id = p_user_id
        )
        or public.is_docukeep_staff()
        or exists (
            select 1
            from public.docukeep_document_access a
            where a.document_id = p_document_id
              and (
                  a.user_id = p_user_id
                  or (a.group_id is not null
                      and public.docukeep_is_group_member(a.group_id, p_user_id))
              )
        )
        or exists (
            select 1
            from public.documents d
            where d.id = p_document_id
              and d.folder_id is not null
              and public.docukeep_can_read_folder(d.folder_id, p_user_id)
        )
        );
$$;

revoke all on function public.docukeep_can_read_folder(uuid, uuid) from public, anon;
revoke all on function public.docukeep_can_read_document(uuid, uuid) from public, anon;
grant execute on function public.docukeep_can_read_folder(uuid, uuid) to authenticated;
grant execute on function public.docukeep_can_read_document(uuid, uuid) to authenticated;

-- Check an intended share recipient without exposing profiles through RLS.
-- Only an approved teacher or staff account may call this helper.
create or replace function public.docukeep_is_approved_share_target(p_user_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
    select
        (
            public.is_docukeep_staff()
            or exists (
                select 1 from public.profiles actor
                where actor.id = auth.uid()
                  and actor.role = 'teacher'
                  and actor.status = 'approved'
            )
        )
        and exists (
            select 1 from public.profiles target
            where target.id = p_user_id
              and target.status = 'approved'
              and target.role in ('student','teacher')
        );
$$;
revoke all on function public.docukeep_is_approved_share_target(uuid) from public, anon;
grant execute on function public.docukeep_is_approved_share_target(uuid) to authenticated;

-- 4) Remove Premium-only restrictions from classroom/group sharing.
-- Group creation remains limited to approved teachers (or staff).
drop policy if exists "premium group owner create" on public.docukeep_groups;
drop policy if exists "premium group owner update" on public.docukeep_groups;
drop policy if exists "premium group members read" on public.docukeep_groups;
drop policy if exists "classroom groups read by owner members or staff" on public.docukeep_groups;
create policy "classroom groups read by owner members or staff"
on public.docukeep_groups for select to authenticated
using (
    public.is_docukeep_staff()
    or created_by = auth.uid()
    or public.docukeep_is_group_member(id, auth.uid())
);
drop policy if exists "approved teachers create classrooms" on public.docukeep_groups;
create policy "approved teachers create classrooms"
on public.docukeep_groups for insert to authenticated
with check (
    created_by = auth.uid()
    and (
        public.is_docukeep_staff()
        or exists (
            select 1 from public.profiles p
            where p.id = auth.uid()
              and p.role = 'teacher'
              and p.status = 'approved'
        )
    )
);
drop policy if exists "classroom owners update groups" on public.docukeep_groups;
create policy "classroom owners update groups"
on public.docukeep_groups for update to authenticated
using (public.is_docukeep_staff() or created_by = auth.uid())
with check (public.is_docukeep_staff() or created_by = auth.uid());
drop policy if exists "classroom owners delete groups" on public.docukeep_groups;
create policy "classroom owners delete groups"
on public.docukeep_groups for delete to authenticated
using (public.is_docukeep_staff() or created_by = auth.uid());

-- Group members: owner/staff manages membership; members/owner/staff can read.
drop policy if exists "premium group creator manages members" on public.docukeep_group_members;
drop policy if exists "premium members own read" on public.docukeep_group_members;
drop policy if exists "classroom membership read" on public.docukeep_group_members;
create policy "classroom membership read"
on public.docukeep_group_members for select to authenticated
using (
    public.is_docukeep_staff()
    or user_id = auth.uid()
    or public.docukeep_is_group_owner(group_id, auth.uid())
);
drop policy if exists "classroom owners add members" on public.docukeep_group_members;
create policy "classroom owners add members"
on public.docukeep_group_members for insert to authenticated
with check (
    public.is_docukeep_staff()
    or (
        public.docukeep_is_group_owner(group_id, auth.uid())
        and public.docukeep_is_approved_share_target(user_id)
    )
);
drop policy if exists "classroom owners update members" on public.docukeep_group_members;
create policy "classroom owners update members"
on public.docukeep_group_members for update to authenticated
using (public.is_docukeep_staff() or public.docukeep_is_group_owner(group_id, auth.uid()))
with check (public.is_docukeep_staff() or public.docukeep_is_group_owner(group_id, auth.uid()));
drop policy if exists "classroom owners remove members" on public.docukeep_group_members;
create policy "classroom owners remove members"
on public.docukeep_group_members for delete to authenticated
using (public.is_docukeep_staff() or public.docukeep_is_group_owner(group_id, auth.uid()));

-- 5) Document grants no longer require either party to have Premium.
drop policy if exists "premium document access read" on public.docukeep_document_access;
drop policy if exists "premium document owner manages access" on public.docukeep_document_access;
drop policy if exists "document access grants read by recipients or owner" on public.docukeep_document_access;
create policy "document access grants read by recipients or owner"
on public.docukeep_document_access for select to authenticated
using (
    public.is_docukeep_staff()
    or exists (
        select 1 from public.documents d
        where d.id = document_id and d.owner_id = auth.uid()
    )
    or user_id = auth.uid()
    or (group_id is not null and public.docukeep_is_group_member(group_id, auth.uid()))
);
drop policy if exists "document owners manage access grants" on public.docukeep_document_access;
create policy "document owners manage access grants"
on public.docukeep_document_access for all to authenticated
using (
    public.is_docukeep_staff()
    or exists (
        select 1 from public.documents d
        where d.id = document_id and d.owner_id = auth.uid()
    )
)
with check (
    public.is_docukeep_staff()
    or (
        exists (
            select 1 from public.documents d
            where d.id = document_id and d.owner_id = auth.uid()
        )
        and granted_by = auth.uid()
        and ((user_id is not null and group_id is null)
             or (user_id is null and group_id is not null))
        and (user_id is null or public.docukeep_is_approved_share_target(user_id))
        and (group_id is null or public.docukeep_is_group_owner(group_id, auth.uid()))
    )
);

-- 6) Folder grants: owners/staff manage; recipients and members can read.
drop policy if exists "folder grants read by recipients or owner" on public.docukeep_folder_access;
create policy "folder grants read by recipients or owner"
on public.docukeep_folder_access for select to authenticated
using (
    public.is_docukeep_staff()
    or exists (
        select 1 from public.docukeep_folders f
        where f.id = folder_id and f.owner_id = auth.uid()
    )
    or user_id = auth.uid()
    or (group_id is not null and public.docukeep_is_group_member(group_id, auth.uid()))
);
drop policy if exists "folder owners manage access grants" on public.docukeep_folder_access;
create policy "folder owners manage access grants"
on public.docukeep_folder_access for all to authenticated
using (
    public.is_docukeep_staff()
    or exists (
        select 1 from public.docukeep_folders f
        where f.id = folder_id and f.owner_id = auth.uid()
    )
)
with check (
    public.is_docukeep_staff()
    or (
        exists (
            select 1 from public.docukeep_folders f
            where f.id = folder_id and f.owner_id = auth.uid()
        )
        and granted_by = auth.uid()
        and ((user_id is not null and group_id is null)
             or (user_id is null and group_id is not null))
        and (user_id is null or public.docukeep_is_approved_share_target(user_id))
        and (group_id is null or public.docukeep_is_group_owner(group_id, auth.uid()))
    )
);

-- No direct reads/writes of invite rows. SECURITY DEFINER RPCs are the only path.
revoke all on public.docukeep_group_invites from anon, authenticated;

-- 7) Teacher creates/rotates a class code and invitation token.
create or replace function public.docukeep_create_group_invite(
    p_group_id uuid,
    p_expires_at timestamptz default null
) returns table(join_code text, invite_token text)
language plpgsql security definer
set search_path = public
as $$
declare
    v_code text;
    v_token text;
begin
    if auth.uid() is null then
        raise exception 'Sign in to create a classroom invitation.';
    end if;
    if not (
        public.is_docukeep_staff()
        or exists (
            select 1 from public.docukeep_groups g
            join public.profiles p on p.id = auth.uid()
            where g.id = p_group_id
              and g.created_by = auth.uid()
              and p.role = 'teacher'
              and p.status = 'approved'
        )
    ) then
        raise exception 'Only the classroom teacher can create an invitation.';
    end if;
    if p_expires_at is not null and p_expires_at <= now() then
        raise exception 'Invitation expiration must be in the future.';
    end if;

    update public.docukeep_group_invites
       set disabled_at = now()
     where group_id = p_group_id and disabled_at is null;

    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

    insert into public.docukeep_group_invites
        (group_id, invite_code, invite_token, created_by, expires_at)
    values
        (p_group_id, v_code, v_token, auth.uid(), p_expires_at);

    return query select v_code, v_token;
end;
$$;

create or replace function public.docukeep_disable_group_invite(
    p_group_id uuid
) returns boolean
language plpgsql security definer
set search_path = public
as $$
begin
    if auth.uid() is null or not (
        public.is_docukeep_staff()
        or public.docukeep_is_group_owner(p_group_id, auth.uid())
    ) then
        raise exception 'Only the classroom teacher can disable this invitation.';
    end if;
    update public.docukeep_group_invites
       set disabled_at = now()
     where group_id = p_group_id and disabled_at is null;
    return true;
end;
$$;

-- 8) Student joins immediately using a code OR invitation link token.
create or replace function public.docukeep_join_group(
    p_code text default null,
    p_token text default null
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
    v_group_id uuid;
    v_role text;
    v_status text;
begin
    if auth.uid() is null then
        raise exception 'Sign in before joining a classroom.';
    end if;
    select role, status into v_role, v_status
      from public.profiles where id = auth.uid();
    if v_status is distinct from 'approved' or v_role not in ('student','teacher') then
        raise exception 'Only approved DocuKeep students or teachers can join a classroom.';
    end if;
    if nullif(trim(coalesce(p_code, '')), '') is null
       and nullif(trim(coalesce(p_token, '')), '') is null then
        raise exception 'Enter a class code or open a valid invitation link.';
    end if;

    select i.group_id into v_group_id
      from public.docukeep_group_invites i
     where i.disabled_at is null
       and (i.expires_at is null or i.expires_at > now())
       and (
           (nullif(trim(coalesce(p_code, '')), '') is not null
             and upper(trim(p_code)) = i.invite_code)
           or
           (nullif(trim(coalesce(p_token, '')), '') is not null
             and trim(p_token) = i.invite_token)
       )
     order by i.created_at desc
     limit 1;

    if v_group_id is null then
        raise exception 'This class code or invitation link is invalid, expired, or disabled.';
    end if;

    -- Serialize joins for this group/user pair to avoid duplicate membership rows.
    perform pg_advisory_xact_lock(hashtext(v_group_id::text), hashtext(auth.uid()::text));
    if not exists (
        select 1 from public.docukeep_group_members m
        where m.group_id = v_group_id and m.user_id = auth.uid()
    ) then
        insert into public.docukeep_group_members(group_id, user_id, member_role)
        values (v_group_id, auth.uid(), 'member');
    end if;
    return v_group_id;
end;
$$;


-- Teacher-facing member roster (limited to classroom owner/staff).
create or replace function public.docukeep_list_group_members(p_group_id uuid)
returns table(user_id uuid, full_name text, email text, member_role text, joined_at timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
    if auth.uid() is null or not (
        public.is_docukeep_staff()
        or public.docukeep_is_group_owner(p_group_id, auth.uid())
    ) then
        raise exception 'Only the classroom teacher can view the member list.';
    end if;
    return query
    select m.user_id, p.full_name, p.email, m.member_role, m.created_at
      from public.docukeep_group_members m
      join public.profiles p on p.id = m.user_id
     where m.group_id = p_group_id
     order by m.created_at;
end;
$$;

create or replace function public.docukeep_remove_group_member(
    p_group_id uuid,
    p_user_id uuid
) returns boolean
language plpgsql security definer
set search_path = public
as $$
begin
    if auth.uid() is null or not (
        public.is_docukeep_staff()
        or public.docukeep_is_group_owner(p_group_id, auth.uid())
    ) then
        raise exception 'Only the classroom teacher can remove members.';
    end if;
    if p_user_id = (select g.created_by from public.docukeep_groups g where g.id = p_group_id) then
        raise exception 'The classroom owner cannot be removed.';
    end if;
    delete from public.docukeep_group_members
     where group_id = p_group_id and user_id = p_user_id;
    return true;
end;
$$;

-- Resolve an exact email for a teacher's direct share action without exposing
-- the full profiles table to other users.
create or replace function public.docukeep_find_approved_user(p_email text)
returns table(user_id uuid, full_name text, email text)
language plpgsql stable security definer
set search_path = public
as $$
begin
    if auth.uid() is null or not (
        public.is_docukeep_staff()
        or exists (
            select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'teacher' and p.status = 'approved'
        )
    ) then
        raise exception 'Only approved teachers can look up a sharing recipient.';
    end if;
    return query
    select p.id, p.full_name, p.email
      from public.profiles p
     where lower(p.email) = lower(trim(p_email))
       and p.status = 'approved'
       and p.role in ('student','teacher');
end;
$$;

-- Restrict RPC execution to signed-in users.
revoke all on function public.docukeep_create_group_invite(uuid, timestamptz) from public, anon;
revoke all on function public.docukeep_disable_group_invite(uuid) from public, anon;
revoke all on function public.docukeep_join_group(text, text) from public, anon;
revoke all on function public.docukeep_list_group_members(uuid) from public, anon;
revoke all on function public.docukeep_remove_group_member(uuid, uuid) from public, anon;
revoke all on function public.docukeep_find_approved_user(text) from public, anon;
grant execute on function public.docukeep_create_group_invite(uuid, timestamptz) to authenticated;
grant execute on function public.docukeep_disable_group_invite(uuid) to authenticated;
grant execute on function public.docukeep_join_group(text, text) to authenticated;
grant execute on function public.docukeep_list_group_members(uuid) to authenticated;
grant execute on function public.docukeep_remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.docukeep_find_approved_user(text) to authenticated;

-- 9) Folder read policy recognizes authorized shares; folder editing stays owner-only.
drop policy if exists "folders own or staff read" on public.docukeep_folders;
drop policy if exists "folders own shared or staff read" on public.docukeep_folders;
create policy "folders own shared or staff read"
on public.docukeep_folders for select to authenticated
using (
    owner_id = auth.uid()
    or public.is_docukeep_staff()
    or public.docukeep_can_read_folder(id, auth.uid())
);

-- A document can only be placed in a folder owned by the same account.
create or replace function public.docukeep_validate_document_folder_owner()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
    if new.folder_id is not null and not public.is_docukeep_staff() then
        if not exists (
            select 1 from public.docukeep_folders f
            where f.id = new.folder_id and f.owner_id = new.owner_id
        ) then
            raise exception 'A document can only be moved into a folder owned by its uploader.';
        end if;
    end if;
    return new;
end;
$$;
drop trigger if exists docukeep_validate_document_folder_owner on public.documents;
create trigger docukeep_validate_document_folder_owner
before insert or update of folder_id, owner_id on public.documents
for each row execute function public.docukeep_validate_document_folder_owner();

-- 10) Storage: shared file access follows the exact same document authorization.
drop policy if exists "premium shared documents read" on storage.objects;
drop policy if exists "authorized users read shared documents" on storage.objects;
create policy "authorized users read shared documents"
on storage.objects for select to authenticated
using (
    bucket_id = 'docukeep-files'
    and exists (
        select 1 from public.documents d
        where d.storage_path = objects.name
          and public.docukeep_can_read_document(d.id, auth.uid())
    )
);

commit;

-- After running this migration:
-- * Approved teachers can create groups without Premium.
-- * Students/approved teachers join with docukeep_join_group(code, null) or
--   docukeep_join_group(null, token); membership is immediate.
-- * Teachers create/rotate invitations with docukeep_create_group_invite(group_id).
-- * Teachers share folders by inserting docukeep_folder_access rows.
-- * Teachers share individual documents through docukeep_document_access.
-- * Folder access is inherited by nested folders and files inside them.
-- * Private files remain private unless the owner explicitly shares them.
