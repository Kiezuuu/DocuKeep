-- Run this after the existing DocuKeep profile/direct-upload migration.

-- ============================================================
-- USER PROFILE DIRECTORY
-- Authenticated users can see approved users' public profile fields.
-- Only approved staff can see email, account status, and join date.
-- ============================================================
CREATE OR REPLACE FUNCTION public.docukeep_list_profiles()
RETURNS TABLE (
  id uuid,
  full_name text,
  username text,
  department text,
  avatar_url text,
  role text,
  email text,
  status text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_staff boolean := public.is_docukeep_staff();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name::text,
    p.username::text,
    p.department::text,
    p.avatar_url::text,
    p.role::text,
    CASE WHEN v_is_staff THEN p.email::text ELSE NULL::text END,
    CASE WHEN v_is_staff THEN p.status::text ELSE NULL::text END,
    CASE WHEN v_is_staff THEN p.created_at ELSE NULL::timestamptz END
  FROM public.profiles p
  WHERE v_is_staff OR p.status = 'approved'
  ORDER BY lower(coalesce(p.full_name, ''));
END;
$$;

REVOKE ALL ON FUNCTION public.docukeep_list_profiles() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.docukeep_list_profiles() TO authenticated;

NOTIFY pgrst, 'reload schema';
