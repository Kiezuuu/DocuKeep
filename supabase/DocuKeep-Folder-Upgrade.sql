-- DocuKeep folder hierarchy + server-side Premium color enforcement
-- Run this once in Supabase SQL Editor.

alter table public.docukeep_folders
    add column if not exists parent_id uuid
    references public.docukeep_folders(id) on delete restrict;

create index if not exists docukeep_folders_parent_id_idx
    on public.docukeep_folders(parent_id);

-- Ensure a folder can only be nested under another folder owned by the same user.
create or replace function public.docukeep_validate_folder_parent_and_color()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
    parent_owner uuid;
begin
    if new.parent_id is not null then
        if new.parent_id = new.id then
            raise exception 'A folder cannot be its own parent.';
        end if;

        select owner_id into parent_owner
        from public.docukeep_folders
        where id = new.parent_id;

        if parent_owner is null or parent_owner <> new.owner_id then
            raise exception 'The parent folder must belong to the same account.';
        end if;
    end if;

    -- The default Free color is allowed. Any custom color requires active Premium.
    if tg_op = 'INSERT' then
        if coalesce(new.color, '#2862a5') <> '#2862a5'
           and not coalesce(public.docukeep_has_active_premium(), false) then
            raise exception 'Custom folder colors require an active Premium subscription.';
        end if;
    elsif new.color is distinct from old.color then
        if coalesce(new.color, '#2862a5') <> '#2862a5'
           and not coalesce(public.docukeep_has_active_premium(), false) then
            raise exception 'Custom folder colors require an active Premium subscription.';
        end if;
    end if;

    return new;
end;
$$;

drop trigger if exists docukeep_validate_folder_parent_and_color
    on public.docukeep_folders;

create trigger docukeep_validate_folder_parent_and_color
before insert or update of parent_id, color
on public.docukeep_folders
for each row
execute function public.docukeep_validate_folder_parent_and_color();
