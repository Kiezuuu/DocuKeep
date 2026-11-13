-- DocuKeep: separate profile-picture update from personal-name editing
-- Run this patch in Supabase SQL Editor. Safe to run more than once.

CREATE OR REPLACE FUNCTION public.docukeep_update_my_profile_picture(p_path text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;

  -- A user may only reference a file inside their own UUID folder.
  IF p_path IS NOT NULL AND p_path <> '' AND
     p_path !~ ('^' || v_uid::text || '/profile/avatar-[0-9]+\.jpg$') THEN
    RAISE EXCEPTION 'Invalid profile picture path.';
  END IF;

  UPDATE public.profiles
  SET profile_picture_path = nullif(p_path, ''),
      avatar_url = NULL
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Your existing DocuKeep profile was not found.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.docukeep_update_my_profile_picture(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.docukeep_update_my_profile_picture(text) TO authenticated;
