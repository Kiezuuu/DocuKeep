-- ============================================================
-- DOCUKEEP PROFILE CUSTOMIZATION + DIRECT DOCUMENT UPLOAD
-- Run this in Supabase SQL Editor after the existing DocuKeep setup.
-- This does NOT remove student/teacher account approval.
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS username text,
  ADD COLUMN IF NOT EXISTS avatar_url text;

-- Usernames are unique regardless of letter casing. Existing users may
-- leave username NULL until they customize their profile.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_unique
  ON public.profiles (lower(username))
  WHERE username IS NOT NULL AND btrim(username) <> '';

-- Users can change only their own public profile fields through this RPC.
-- Role, email, account status, and account ID cannot be changed by this function.
CREATE OR REPLACE FUNCTION public.docukeep_update_my_profile(
  p_full_name text,
  p_username text,
  p_department text DEFAULT NULL,
  p_avatar_url text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_username text := lower(btrim(coalesce(p_username, '')));
  v_avatar_url text := nullif(btrim(coalesce(p_avatar_url, '')), '');
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;

  IF length(btrim(coalesce(p_full_name, ''))) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Display name must contain 1 to 100 characters.';
  END IF;

  IF v_username !~ '^[a-z0-9_]{3,30}$' THEN
    RAISE EXCEPTION 'Username must be 3 to 30 letters, numbers, or underscores.';
  END IF;

  IF v_avatar_url IS NOT NULL AND v_avatar_url !~* '^https://' THEN
    RAISE EXCEPTION 'Profile picture URL must use HTTPS.';
  END IF;

  UPDATE public.profiles
  SET full_name = btrim(p_full_name),
      username = v_username,
      department = nullif(btrim(coalesce(p_department, '')), ''),
      avatar_url = v_avatar_url
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Your DocuKeep profile was not found.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.docukeep_update_my_profile(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.docukeep_update_my_profile(text,text,text,text) TO authenticated;

NOTIFY pgrst, 'reload schema';
