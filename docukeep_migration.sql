
-- ============================================================
-- DOCUKEEP | COMPLETE DATABASE SETUP
-- Supabase PostgreSQL
-- ============================================================
-- Roles:
--   student: personal @gmail.com
--   teacher: official @deped.gov.ph
--   staff: manually provisioned, approved only
--
-- Storage:
--   Bucket: docukeep-files
--   Private: true
--   Maximum file size: 25 MB
--
-- IMPORTANT:
-- This script does not create Auth users or passwords.
-- Existing Auth users and documents are preserved.
-- ============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 1. PROFILES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name text NOT NULL DEFAULT 'New user',
    email text NOT NULL,
    role text NOT NULL DEFAULT 'student'
        CHECK (role IN ('student', 'teacher', 'staff')),
    department text,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS full_name text DEFAULT 'New user',
    ADD COLUMN IF NOT EXISTS email text,
    ADD COLUMN IF NOT EXISTS role text DEFAULT 'student',
    ADD COLUMN IF NOT EXISTS department text,
    ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

UPDATE public.profiles
SET
    full_name = COALESCE(NULLIF(full_name, ''), 'New user'),
    email = lower(COALESCE(email, '')),
    role = COALESCE(role, 'student'),
    status = COALESCE(status, 'pending'),
    created_at = COALESCE(created_at, now());

CREATE INDEX IF NOT EXISTS profiles_role_status_idx
    ON public.profiles(role, status);

CREATE INDEX IF NOT EXISTS profiles_email_idx
    ON public.profiles(email);


-- ============================================================
-- 2. DOCUMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    owner_name text,
    title text NOT NULL,
    category text NOT NULL DEFAULT 'Other',
    school_year text,
    department text,
    due_date date,
    submission_type text,
    description text,
    storage_path text NOT NULL,
    file_name text NOT NULL,
    mime_type text,
    size_bytes bigint NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'needs_revision', 'rejected')),
    reviewed_at timestamptz,
    reviewed_by uuid REFERENCES public.profiles(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.documents
    ADD COLUMN IF NOT EXISTS owner_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS owner_name text,
    ADD COLUMN IF NOT EXISTS title text,
    ADD COLUMN IF NOT EXISTS category text DEFAULT 'Other',
    ADD COLUMN IF NOT EXISTS school_year text,
    ADD COLUMN IF NOT EXISTS department text,
    ADD COLUMN IF NOT EXISTS due_date date,
    ADD COLUMN IF NOT EXISTS submission_type text,
    ADD COLUMN IF NOT EXISTS description text,
    ADD COLUMN IF NOT EXISTS storage_path text,
    ADD COLUMN IF NOT EXISTS file_name text,
    ADD COLUMN IF NOT EXISTS mime_type text,
    ADD COLUMN IF NOT EXISTS size_bytes bigint DEFAULT 0,
    ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
    ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES public.profiles(id),
    ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now(),
    ADD COLUMN IF NOT EXISTS folder_id uuid,
    ADD COLUMN IF NOT EXISTS sha256 text;

CREATE INDEX IF NOT EXISTS documents_owner_created_idx
    ON public.documents(owner_id, created_at DESC);

CREATE INDEX IF NOT EXISTS documents_status_idx
    ON public.documents(status);

CREATE INDEX IF NOT EXISTS documents_due_date_idx
    ON public.documents(due_date)
    WHERE due_date IS NOT NULL;


-- ============================================================
-- 3. FOLDERS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.docukeep_folders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    name text NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
    color text NOT NULL DEFAULT '#2862a5'
        CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(owner_id, name)
);

ALTER TABLE public.documents
    DROP CONSTRAINT IF EXISTS documents_folder_id_fkey;

ALTER TABLE public.documents
    ADD CONSTRAINT documents_folder_id_fkey
    FOREIGN KEY (folder_id)
    REFERENCES public.docukeep_folders(id)
    ON DELETE SET NULL;


-- ============================================================
-- 4. NOTIFICATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.docukeep_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title text NOT NULL,
    message text NOT NULL,
    notification_type text NOT NULL DEFAULT 'general',
    related_document_id uuid REFERENCES public.documents(id) ON DELETE CASCADE,
    dedupe_key text UNIQUE,
    is_read boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_user_created_idx
    ON public.docukeep_notifications(user_id, created_at DESC);


-- ============================================================
-- 5. PREMIUM ENTITLEMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.docukeep_entitlements (
    user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    plan text NOT NULL DEFAULT 'free'
        CHECK (plan IN ('free', 'premium')),
    storage_limit_bytes bigint NOT NULL DEFAULT 26214400
        CHECK (storage_limit_bytes > 0),
    active boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.docukeep_entitlements (
    user_id, plan, storage_limit_bytes, active
)
SELECT id, 'free', 26214400, true
FROM public.profiles
ON CONFLICT (user_id) DO NOTHING;


-- ============================================================
-- 6. GROUPS AND MEMBERS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.docukeep_groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
    created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.docukeep_group_members (
    group_id uuid NOT NULL REFERENCES public.docukeep_groups(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    member_role text NOT NULL DEFAULT 'member'
        CHECK (member_role IN ('owner', 'member')),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, user_id)
);


-- ============================================================
-- 7. DOCUMENT SHARING
-- ============================================================

CREATE TABLE IF NOT EXISTS public.docukeep_document_access (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    group_id uuid REFERENCES public.docukeep_groups(id) ON DELETE CASCADE,
    permission text NOT NULL CHECK (permission IN ('view', 'edit')),
    granted_by uuid NOT NULL REFERENCES public.profiles(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (
        (user_id IS NOT NULL AND group_id IS NULL)
        OR
        (user_id IS NULL AND group_id IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS document_access_user_unique
    ON public.docukeep_document_access(document_id, user_id)
    WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS document_access_group_unique
    ON public.docukeep_document_access(document_id, group_id)
    WHERE group_id IS NOT NULL;


-- ============================================================
-- 8. OFFLINE UPLOAD TRACKING
-- ============================================================

CREATE TABLE IF NOT EXISTS public.docukeep_upload_sync (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    storage_path text NOT NULL,
    file_name text NOT NULL,
    file_size bigint NOT NULL CHECK (file_size >= 0),
    state text NOT NULL DEFAULT 'queued'
        CHECK (state IN ('queued', 'uploading', 'uploaded', 'failed')),
    last_error text,
    updated_at timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- 9. STAFF PROVISIONING
-- UUIDs must already exist in auth.users.
-- ============================================================

INSERT INTO public.profiles (
    id, full_name, email, role, department, status
)
SELECT
    u.id,
    COALESCE(
        NULLIF(u.raw_user_meta_data->>'full_name', ''),
        'DocuKeep Staff'
    ),
    lower(u.email),
    'staff',
    'Administration',
    'approved'
FROM auth.users u
WHERE u.id = '4e6c5f42-e751-4fa3-ad92-5746d9ee8323'::uuid
ON CONFLICT (id) DO UPDATE SET
    role = 'staff',
    status = 'approved',
    department = 'Administration',
    email = EXCLUDED.email;


INSERT INTO public.profiles (
    id, full_name, email, role, department, status
)
SELECT
    u.id,
    'Aimerck',
    lower(u.email),
    'staff',
    'G11',
    'approved'
FROM auth.users u
WHERE u.id = '0fc4f3df-845a-44a6-b60f-516ac9882c7e'::uuid
ON CONFLICT (id) DO UPDATE SET
    full_name = 'Aimerck',
    email = EXCLUDED.email,
    role = 'staff',
    department = 'G11',
    status = 'approved';


-- ============================================================
-- 10. SECURITY HELPER FUNCTIONS
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_docukeep_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role = 'staff'
          AND p.status = 'approved'
    );
$$;


CREATE OR REPLACE FUNCTION public.docukeep_is_approved_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.status = 'approved'
    );
$$;


CREATE OR REPLACE FUNCTION public.docukeep_is_group_member(
    p_group_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.docukeep_group_members m
        WHERE m.group_id = p_group_id
          AND m.user_id = p_user_id
    );
$$;


CREATE OR REPLACE FUNCTION public.docukeep_is_group_owner(
    p_group_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.docukeep_groups g
        WHERE g.id = p_group_id
          AND g.created_by = p_user_id
    );
$$;


CREATE OR REPLACE FUNCTION public.docukeep_can_read_document(
    p_document_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        EXISTS (
            SELECT 1
            FROM public.documents d
            WHERE d.id = p_document_id
              AND d.owner_id = p_user_id
        )
        OR EXISTS (
            SELECT 1
            FROM public.docukeep_document_access a
            WHERE a.document_id = p_document_id
              AND (
                  a.user_id = p_user_id
                  OR (
                      a.group_id IS NOT NULL
                      AND public.docukeep_is_group_member(
                          a.group_id, p_user_id
                      )
                  )
              )
        );
$$;


CREATE OR REPLACE FUNCTION public.can_read_shared_document(
    p_document_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.docukeep_can_read_document(
        p_document_id, auth.uid()
    );
$$;


REVOKE ALL ON FUNCTION public.is_docukeep_staff() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.docukeep_is_approved_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.docukeep_is_group_member(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.docukeep_is_group_owner(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.docukeep_can_read_document(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_read_shared_document(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_docukeep_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.docukeep_is_approved_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.docukeep_is_group_member(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.docukeep_is_group_owner(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.docukeep_can_read_document(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_read_shared_document(uuid) TO authenticated;



-- ============================================================
-- DOCUKEEP: UPDATED AUTH SIGNUP TRIGGER
-- Students and Teachers can use personal Gmail accounts.
-- New registrations will have PENDING status.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.handle_docukeep_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    requested_role text;
    mail_domain text;
BEGIN
    -- Get the role selected during registration
    requested_role :=
        COALESCE(new.raw_user_meta_data->>'requested_role', '');

    -- Only allow student and teacher self-registration
    IF requested_role NOT IN ('student', 'teacher') THEN
        RETURN new;
    END IF;

    -- Get the email domain
    mail_domain := lower(
        split_part(COALESCE(new.email, ''), '@', 2)
    );

    -- Students and teachers must use Gmail
    IF requested_role IN ('student', 'teacher')
       AND mail_domain <> 'gmail.com' THEN
        RAISE EXCEPTION
            'Students and teachers must register using a personal Gmail address.';
    END IF;

    -- Create the user's profile
    INSERT INTO public.profiles (
        id,
        full_name,
        email,
        role,
        department,
        status
    )
    VALUES (
        new.id,
        COALESCE(
            NULLIF(new.raw_user_meta_data->>'full_name', ''),
            'New user'
        ),
        lower(new.email),
        requested_role,
        NULLIF(
            new.raw_user_meta_data->>'department',
            ''
        ),
        'pending'
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN new;
END;
$$;

-- Recreate the signup trigger
DROP TRIGGER IF EXISTS
    on_docukeep_auth_user_created
ON auth.users;

CREATE TRIGGER on_docukeep_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_docukeep_signup();

-- Reload Supabase API schema
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- END OF DOCUKEEP SIGNUP MIGRATION
-- ============================================================


-- ============================================================
-- 12. ACCOUNT APPROVAL RPC
-- ============================================================

CREATE OR REPLACE FUNCTION public.approve_docukeep_profile(
    p_user_id uuid,
    p_status text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_role text;
BEGIN
    IF NOT public.is_docukeep_staff() THEN
        RAISE EXCEPTION 'Only approved staff can manage account approvals.';
    END IF;

    IF p_status NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'Invalid account status.';
    END IF;

    SELECT role INTO target_role
    FROM public.profiles
    WHERE id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile not found.';
    END IF;

    IF target_role NOT IN ('student', 'teacher') THEN
        RAISE EXCEPTION 'Only student and teacher accounts can be reviewed.';
    END IF;

    UPDATE public.profiles
    SET status = p_status
    WHERE id = p_user_id;

    INSERT INTO public.docukeep_notifications (
        user_id, title, message, notification_type
    )
    VALUES (
        p_user_id,
        CASE WHEN p_status = 'approved'
            THEN 'Account approved'
            ELSE 'Account rejected'
        END,
        CASE WHEN p_status = 'approved'
            THEN 'Your DocuKeep account has been approved. You can now sign in.'
            ELSE 'Your DocuKeep account registration was rejected. Please contact the administrator.'
        END,
        'account'
    );

    RETURN true;
END;
$$;


-- ============================================================
-- 13. STAFF ROLE MANAGEMENT RPC
-- ============================================================

CREATE OR REPLACE FUNCTION public.manage_docukeep_user_role(
    p_user_id uuid,
    p_new_role text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    old_role text;
    staff_count integer;
BEGIN
    IF NOT public.is_docukeep_staff() THEN
        RAISE EXCEPTION 'Only approved staff can change user roles.';
    END IF;

    IF p_new_role NOT IN ('student', 'teacher', 'staff') THEN
        RAISE EXCEPTION 'Invalid role.';
    END IF;

    IF p_user_id = auth.uid() AND p_new_role <> 'staff' THEN
        RAISE EXCEPTION 'You cannot remove your own staff role.';
    END IF;

    SELECT role INTO old_role
    FROM public.profiles
    WHERE id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile not found.';
    END IF;

    IF old_role = 'staff' AND p_new_role <> 'staff' THEN
        SELECT count(*) INTO staff_count
        FROM public.profiles
        WHERE role = 'staff'
          AND status = 'approved';

        IF staff_count <= 1 THEN
            RAISE EXCEPTION 'Cannot remove the last approved staff account.';
        END IF;
    END IF;

    UPDATE public.profiles
    SET
        role = p_new_role,
        status = CASE
            WHEN p_new_role = 'staff' THEN 'approved'
            ELSE status
        END
    WHERE id = p_user_id;

    RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_docukeep_profile(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.manage_docukeep_user_role(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.approve_docukeep_profile(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.manage_docukeep_user_role(uuid, text) TO authenticated;


-- ============================================================
-- 14. ENABLE RLS
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.docukeep_folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.docukeep_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.docukeep_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.docukeep_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.docukeep_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.docukeep_document_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.docukeep_upload_sync ENABLE ROW LEVEL SECURITY;


-- Remove previous policies on these tables so that old permissive
-- policies cannot accidentally grant access alongside the new rules.

DO $$
DECLARE
    t text;
    p record;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'profiles',
        'documents',
        'docukeep_folders',
        'docukeep_notifications',
        'docukeep_entitlements',
        'docukeep_groups',
        'docukeep_group_members',
        'docukeep_document_access',
        'docukeep_upload_sync'
    ]
    LOOP
        FOR p IN
            SELECT policyname
            FROM pg_policies
            WHERE schemaname = 'public'
              AND tablename = t
        LOOP
            EXECUTE format(
                'DROP POLICY IF EXISTS %I ON public.%I',
                p.policyname,
                t
            );
        END LOOP;
    END LOOP;
END;
$$;


-- ============================================================
-- 15. PROFILE POLICIES
-- ============================================================

CREATE POLICY "profiles own or staff read"
ON public.profiles
FOR SELECT TO authenticated
USING (
    id = auth.uid()
    OR public.is_docukeep_staff()
);

CREATE POLICY "profiles staff update"
ON public.profiles
FOR UPDATE TO authenticated
USING (public.is_docukeep_staff())
WITH CHECK (public.is_docukeep_staff());


-- ============================================================
-- 16. DOCUMENT POLICIES
-- ============================================================

CREATE POLICY "read own shared documents or staff"
ON public.documents
FOR SELECT TO authenticated
USING (
    owner_id = auth.uid()
    OR public.is_docukeep_staff()
    OR public.docukeep_can_read_document(id, auth.uid())
);

CREATE POLICY "documents approved owner insert"
ON public.documents
FOR INSERT TO authenticated
WITH CHECK (
    owner_id = auth.uid()
    AND EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.status = 'approved'
          AND p.role IN ('student', 'teacher')
    )
);

CREATE POLICY "documents owner update"
ON public.documents
FOR UPDATE TO authenticated
USING (
    owner_id = auth.uid()
    AND public.docukeep_is_approved_user()
)
WITH CHECK (
    owner_id = auth.uid()
    AND public.docukeep_is_approved_user()
);

CREATE POLICY "documents staff update"
ON public.documents
FOR UPDATE TO authenticated
USING (public.is_docukeep_staff())
WITH CHECK (public.is_docukeep_staff());

CREATE POLICY "documents owner or staff delete"
ON public.documents
FOR DELETE TO authenticated
USING (
    owner_id = auth.uid()
    OR public.is_docukeep_staff()
);


-- ============================================================
-- 17. FOLDER POLICIES
-- ============================================================

CREATE POLICY "folders own or staff read"
ON public.docukeep_folders
FOR SELECT TO authenticated
USING (
    owner_id = auth.uid()
    OR public.is_docukeep_staff()
);

CREATE POLICY "folders owner insert"
ON public.docukeep_folders
FOR INSERT TO authenticated
WITH CHECK (
    owner_id = auth.uid()
    AND public.docukeep_is_approved_user()
    AND NOT public.is_docukeep_staff()
);

CREATE POLICY "folders owner update"
ON public.docukeep_folders
FOR UPDATE TO authenticated
USING (
    owner_id = auth.uid()
    AND public.docukeep_is_approved_user()
)
WITH CHECK (
    owner_id = auth.uid()
    AND public.docukeep_is_approved_user()
);

CREATE POLICY "folders owner or staff delete"
ON public.docukeep_folders
FOR DELETE TO authenticated
USING (
    owner_id = auth.uid()
    OR public.is_docukeep_staff()
);


-- ============================================================
-- 18. NOTIFICATION POLICIES
-- ============================================================

CREATE POLICY "notifications own read"
ON public.docukeep_notifications
FOR SELECT TO authenticated
USING (
    user_id = auth.uid()
    OR public.is_docukeep_staff()
);

CREATE POLICY "notifications own update"
ON public.docukeep_notifications
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

REVOKE INSERT, DELETE
ON public.docukeep_notifications
FROM anon, authenticated;

GRANT SELECT, UPDATE
ON public.docukeep_notifications
TO authenticated;


-- ============================================================
-- 19. ENTITLEMENT POLICIES
-- ============================================================

CREATE POLICY "entitlement own read"
ON public.docukeep_entitlements
FOR SELECT TO authenticated
USING (
    user_id = auth.uid()
    OR public.is_docukeep_staff()
);

CREATE POLICY "entitlement staff manage"
ON public.docukeep_entitlements
FOR ALL TO authenticated
USING (public.is_docukeep_staff())
WITH CHECK (public.is_docukeep_staff());


-- ============================================================
-- 20. GROUP POLICIES
-- ============================================================

CREATE POLICY "group members read"
ON public.docukeep_groups
FOR SELECT TO authenticated
USING (
    public.is_docukeep_staff()
    OR created_by = auth.uid()
    OR public.docukeep_is_group_member(id, auth.uid())
);

CREATE POLICY "group owner create"
ON public.docukeep_groups
FOR INSERT TO authenticated
WITH CHECK (
    created_by = auth.uid()
    AND public.docukeep_is_approved_user()
);

CREATE POLICY "group owner update"
ON public.docukeep_groups
FOR UPDATE TO authenticated
USING (
    created_by = auth.uid()
    OR public.is_docukeep_staff()
)
WITH CHECK (
    created_by = auth.uid()
    OR public.is_docukeep_staff()
);

CREATE POLICY "group owner delete"
ON public.docukeep_groups
FOR DELETE TO authenticated
USING (
    created_by = auth.uid()
    OR public.is_docukeep_staff()
);


-- ============================================================
-- 21. GROUP MEMBER POLICIES
-- ============================================================

CREATE POLICY "members own read"
ON public.docukeep_group_members
FOR SELECT TO authenticated
USING (
    user_id = auth.uid()
    OR public.docukeep_is_group_owner(group_id, auth.uid())
    OR public.is_docukeep_staff()
);

CREATE POLICY "group creator manages members"
ON public.docukeep_group_members
FOR ALL TO authenticated
USING (
    public.docukeep_is_group_owner(group_id, auth.uid())
    OR public.is_docukeep_staff()
)
WITH CHECK (
    public.docukeep_is_group_owner(group_id, auth.uid())
    OR public.is_docukeep_staff()
);


-- ============================================================
-- 22. DOCUMENT ACCESS POLICIES
-- ============================================================

CREATE POLICY "document access read"
ON public.docukeep_document_access
FOR SELECT TO authenticated
USING (
    public.docukeep_can_read_document(document_id, auth.uid())
    OR public.is_docukeep_staff()
);

CREATE POLICY "document owner manages access"
ON public.docukeep_document_access
FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.documents d
        WHERE d.id = document_id
          AND d.owner_id = auth.uid()
    )
    OR public.is_docukeep_staff()
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.documents d
        WHERE d.id = document_id
          AND d.owner_id = auth.uid()
    )
    OR public.is_docukeep_staff()
);


-- ============================================================
-- 23. OFFLINE UPLOAD POLICIES
-- ============================================================

CREATE POLICY "upload sync own all"
ON public.docukeep_upload_sync
FOR ALL TO authenticated
USING (
    owner_id = auth.uid()
    OR public.is_docukeep_staff()
)
WITH CHECK (
    owner_id = auth.uid()
    OR public.is_docukeep_staff()
);


-- ============================================================
-- 24. TABLE PRIVILEGES
-- ============================================================

GRANT USAGE ON SCHEMA public TO authenticated;

GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (full_name, department)
ON public.profiles TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.documents TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.docukeep_folders TO authenticated;

GRANT SELECT, UPDATE
ON public.docukeep_notifications TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.docukeep_entitlements TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.docukeep_groups TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.docukeep_group_members TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.docukeep_document_access TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.docukeep_upload_sync TO authenticated;


-- ============================================================
-- 25. PRIVATE STORAGE BUCKET
-- ============================================================

INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'docukeep-files',
    'docukeep-files',
    false,
    26214400,
    ARRAY[
        'application/pdf',
        'image/png',
        'image/jpeg',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-powerpoint',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'text/plain'
    ]
)
ON CONFLICT (id)
DO UPDATE SET
    public = false,
    file_size_limit = 26214400,
    allowed_mime_types = EXCLUDED.allowed_mime_types;


-- Owner uploads into their own UUID folder.
CREATE POLICY "docukeep owner upload"
ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'docukeep-files'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND public.docukeep_is_approved_user()
    AND NOT public.is_docukeep_staff()
);


-- Owner and staff can read stored files.
CREATE POLICY "docukeep owner or staff read"
ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'docukeep-files'
    AND (
        (storage.foldername(name))[1] = auth.uid()::text
        OR public.is_docukeep_staff()
    )
);


-- Explicitly shared files can be read by authorized recipients.
CREATE POLICY "shared documents read"
ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'docukeep-files'
    AND EXISTS (
        SELECT 1
        FROM public.documents d
        WHERE d.storage_path = name
          AND public.docukeep_can_read_document(d.id, auth.uid())
    )
);


CREATE POLICY "docukeep owner update"
ON storage.objects
FOR UPDATE TO authenticated
USING (
    bucket_id = 'docukeep-files'
    AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
    bucket_id = 'docukeep-files'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND public.docukeep_is_approved_user()
);


CREATE POLICY "docukeep owner or staff delete"
ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'docukeep-files'
    AND (
        (storage.foldername(name))[1] = auth.uid()::text
        OR public.is_docukeep_staff()
    )
);


-- ============================================================
-- 26. DEADLINE NOTIFICATIONS
-- Call this function manually or schedule it with pg_cron.
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_docukeep_deadline_notifications()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    inserted_count integer;
BEGIN
    INSERT INTO public.docukeep_notifications (
        user_id,
        title,
        message,
        notification_type,
        related_document_id,
        dedupe_key
    )
    SELECT
        d.owner_id,
        CASE
            WHEN d.due_date = current_date + 1 THEN 'Deadline tomorrow'
            WHEN d.due_date = current_date + 3 THEN 'Deadline in 3 days'
            ELSE 'Deadline in 7 days'
        END,
        format(
            '%s is due on %s.',
            d.title,
            to_char(d.due_date, 'Mon DD, YYYY')
        ),
        'deadline',
        d.id,
        'deadline:' || d.id::text || ':' ||
        d.due_date::text || ':' ||
        (d.due_date - current_date)::text
    FROM public.documents d
    JOIN public.profiles p
      ON p.id = d.owner_id
     AND p.status = 'approved'
    WHERE d.due_date IN (
        current_date + 1,
        current_date + 3,
        current_date + 7
    )
      AND d.status NOT IN ('approved', 'rejected')
    ON CONFLICT (dedupe_key) DO NOTHING;

    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION
    public.generate_docukeep_deadline_notifications()
FROM PUBLIC, anon, authenticated;


-- ============================================================
-- 27. DEFAULT ENTITLEMENT FOR NEW PROFILES
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_docukeep_default_entitlement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.docukeep_entitlements (
        user_id, plan, storage_limit_bytes, active
    )
    VALUES (
        NEW.id, 'free', 26214400, true
    )
    ON CONFLICT (user_id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS docukeep_profile_entitlement_trigger
ON public.profiles;

CREATE TRIGGER docukeep_profile_entitlement_trigger
AFTER INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.create_docukeep_default_entitlement();

REVOKE ALL ON FUNCTION
    public.create_docukeep_default_entitlement()
FROM PUBLIC;


-- ============================================================
-- 28. FINAL SCHEMA RELOAD
-- ============================================================

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- END OF DOCUKEEP SETUP
-- ============================================================
