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
