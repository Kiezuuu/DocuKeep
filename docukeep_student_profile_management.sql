-- ============================================================
-- DOCUKEEP: STUDENT PROFILE MANAGEMENT
-- Run AFTER docukeep_profile_direct_upload_migration.sql.
-- Safe/additive: does not create Auth users or duplicate profiles.
-- ============================================================

-- 1. Extend the existing authenticated profile row.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS username text,
  ADD COLUMN IF NOT EXISTS avatar_url text,
  ADD COLUMN IF NOT EXISTS student_id text,
  ADD COLUMN IF NOT EXISTS contact_number text,
  ADD COLUMN IF NOT EXISTS birthday date,
  ADD COLUMN IF NOT EXISTS gender text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS bio text,
  ADD COLUMN IF NOT EXISTS school_name text,
  ADD COLUMN IF NOT EXISTS college_department text,
  ADD COLUMN IF NOT EXISTS course_program text,
  ADD COLUMN IF NOT EXISTS year_level text,
  ADD COLUMN IF NOT EXISTS section text,
  ADD COLUMN IF NOT EXISTS student_status text,
  ADD COLUMN IF NOT EXISTS academic_year text,
  ADD COLUMN IF NOT EXISTS profile_picture_path text,
  ADD COLUMN IF NOT EXISTS cover_photo_path text;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_unique
  ON public.profiles (lower(username))
  WHERE username IS NOT NULL AND btrim(username) <> '';

CREATE INDEX IF NOT EXISTS profiles_student_id_idx
  ON public.profiles(student_id) WHERE student_id IS NOT NULL AND btrim(student_id) <> '';

-- 2. Private bucket for profile photos and personal academic files.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'docukeep-profile-files',
  'docukeep-profile-files',
  false,
  26214400,
  ARRAY[
    'image/jpeg','image/png','image/webp','image/gif',
    'application/pdf','text/plain',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 26214400,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage path format: <auth.uid()>/profile/... and <auth.uid()>/files/...
DROP POLICY IF EXISTS "DocuKeep profile files read own or staff" ON storage.objects;
CREATE POLICY "DocuKeep profile files read own or staff"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'docukeep-profile-files'
  AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_docukeep_staff())
);

DROP POLICY IF EXISTS "DocuKeep profile files upload own" ON storage.objects;
CREATE POLICY "DocuKeep profile files upload own"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'docukeep-profile-files'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "DocuKeep profile files update own" ON storage.objects;
CREATE POLICY "DocuKeep profile files update own"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'docukeep-profile-files' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'docukeep-profile-files' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "DocuKeep profile files delete own or staff" ON storage.objects;
CREATE POLICY "DocuKeep profile files delete own or staff"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'docukeep-profile-files'
  AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_docukeep_staff())
);

-- 3. Metadata for files attached to a user's own profile.
CREATE TABLE IF NOT EXISTS public.docukeep_profile_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  file_name text NOT NULL CHECK (length(btrim(file_name)) BETWEEN 1 AND 255),
  category text NOT NULL DEFAULT 'School document',
  storage_path text NOT NULL UNIQUE,
  mime_type text NOT NULL DEFAULT 'application/octet-stream',
  size_bytes bigint NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS docukeep_profile_files_owner_created_idx
  ON public.docukeep_profile_files(owner_id, created_at DESC);

ALTER TABLE public.docukeep_profile_files ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profile files owner or staff read" ON public.docukeep_profile_files;
CREATE POLICY "Profile files owner or staff read"
ON public.docukeep_profile_files FOR SELECT TO authenticated
USING (owner_id = auth.uid() OR public.is_docukeep_staff());

DROP POLICY IF EXISTS "Profile files owner insert" ON public.docukeep_profile_files;
CREATE POLICY "Profile files owner insert"
ON public.docukeep_profile_files FOR INSERT TO authenticated
WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "Profile files owner update" ON public.docukeep_profile_files;
CREATE POLICY "Profile files owner update"
ON public.docukeep_profile_files FOR UPDATE TO authenticated
USING (owner_id = auth.uid() OR public.is_docukeep_staff())
WITH CHECK (owner_id = auth.uid() OR public.is_docukeep_staff());

DROP POLICY IF EXISTS "Profile files owner or staff delete" ON public.docukeep_profile_files;
CREATE POLICY "Profile files owner or staff delete"
ON public.docukeep_profile_files FOR DELETE TO authenticated
USING (owner_id = auth.uid() OR public.is_docukeep_staff());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.docukeep_profile_files TO authenticated;
REVOKE ALL ON public.docukeep_profile_files FROM anon;

-- 4. Update only the authenticated user's own profile.
-- Sensitive account fields (id, email, role, status, created_at) are never accepted.
CREATE OR REPLACE FUNCTION public.docukeep_update_student_profile(p_profile_data jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_name text;
  v_username text;
  v_birthday date;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;
  IF jsonb_typeof(p_profile_data) <> 'object' THEN
    RAISE EXCEPTION 'Invalid profile data.';
  END IF;

  v_name := btrim(coalesce(p_profile_data->>'full_name',''));
  IF length(v_name) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Full name must contain 1 to 100 characters.';
  END IF;

  v_username := nullif(lower(btrim(coalesce(p_profile_data->>'username',''))),'');
  IF v_username IS NOT NULL AND v_username !~ '^[a-z0-9_]{3,30}$' THEN
    RAISE EXCEPTION 'Username must be 3 to 30 letters, numbers, or underscores.';
  END IF;

  IF nullif(p_profile_data->>'birthday','') IS NOT NULL THEN
    BEGIN
      v_birthday := (p_profile_data->>'birthday')::date;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'Birthday must be a valid date.';
    END;
    IF v_birthday > CURRENT_DATE THEN
      RAISE EXCEPTION 'Birthday cannot be in the future.';
    END IF;
  END IF;

  UPDATE public.profiles
  SET full_name = v_name,
      username = v_username,
      department = nullif(left(btrim(coalesce(p_profile_data->>'department','')),120),''),
      student_id = nullif(left(btrim(coalesce(p_profile_data->>'student_id','')),60),''),
      contact_number = nullif(left(btrim(coalesce(p_profile_data->>'contact_number','')),40),''),
      birthday = v_birthday,
      gender = nullif(left(btrim(coalesce(p_profile_data->>'gender','')),40),''),
      address = nullif(left(btrim(coalesce(p_profile_data->>'address','')),500),''),
      bio = nullif(left(btrim(coalesce(p_profile_data->>'bio','')),600),''),
      school_name = nullif(left(btrim(coalesce(p_profile_data->>'school_name','')),160),''),
      college_department = nullif(left(btrim(coalesce(p_profile_data->>'college_department','')),160),''),
      course_program = nullif(left(btrim(coalesce(p_profile_data->>'course_program','')),160),''),
      year_level = nullif(left(btrim(coalesce(p_profile_data->>'year_level','')),60),''),
      section = nullif(left(btrim(coalesce(p_profile_data->>'section','')),80),''),
      student_status = nullif(left(btrim(coalesce(p_profile_data->>'student_status','')),40),''),
      academic_year = nullif(left(btrim(coalesce(p_profile_data->>'academic_year','')),30),''),
      profile_picture_path = CASE WHEN p_profile_data ? 'profile_picture_path'
        THEN nullif(p_profile_data->>'profile_picture_path','') ELSE profile_picture_path END,
      cover_photo_path = CASE WHEN p_profile_data ? 'cover_photo_path'
        THEN nullif(p_profile_data->>'cover_photo_path','') ELSE cover_photo_path END
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Your existing DocuKeep profile was not found.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.docukeep_update_student_profile(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.docukeep_update_student_profile(jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';


-- Public directory fields for approved users; staff may also see pending/rejected accounts.
CREATE OR REPLACE FUNCTION public.docukeep_list_profiles()
RETURNS TABLE (id uuid, full_name text, username text, department text, avatar_url text, role text, email text, status text, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_is_staff boolean := public.is_docukeep_staff();
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'You must be signed in.'; END IF;
  RETURN QUERY SELECT p.id,p.full_name::text,p.username::text,p.department::text,p.avatar_url::text,p.role::text,
    CASE WHEN v_is_staff THEN p.email::text ELSE NULL::text END,
    CASE WHEN v_is_staff THEN p.status::text ELSE NULL::text END,
    CASE WHEN v_is_staff THEN p.created_at ELSE NULL::timestamptz END
  FROM public.profiles p WHERE v_is_staff OR p.status='approved'
  ORDER BY lower(coalesce(p.full_name,''));
END; $$;
REVOKE ALL ON FUNCTION public.docukeep_list_profiles() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.docukeep_list_profiles() TO authenticated;

-- 5. Staff-only private profile lookup for the People directory.
CREATE OR REPLACE FUNCTION public.docukeep_admin_get_student_profile(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_profile jsonb;
BEGIN
  IF NOT public.is_docukeep_staff() THEN
    RAISE EXCEPTION 'Staff access required.';
  END IF;
  SELECT jsonb_build_object(
    'id',p.id,'full_name',p.full_name,'username',p.username,'email',p.email,
    'role',p.role,'status',p.status,'created_at',p.created_at,
    'student_id',p.student_id,'contact_number',p.contact_number,'birthday',p.birthday,
    'gender',p.gender,'address',p.address,'bio',p.bio,'school_name',p.school_name,
    'college_department',p.college_department,'course_program',p.course_program,
    'year_level',p.year_level,'section',p.section,'student_status',p.student_status,
    'academic_year',p.academic_year,'department',p.department,
    'profile_picture_path',p.profile_picture_path,'cover_photo_path',p.cover_photo_path
  ) INTO v_profile
  FROM public.profiles p WHERE p.id=p_user_id;
  IF v_profile IS NULL THEN RAISE EXCEPTION 'Student profile not found.'; END IF;
  RETURN v_profile;
END;
$$;
REVOKE ALL ON FUNCTION public.docukeep_admin_get_student_profile(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.docukeep_admin_get_student_profile(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
