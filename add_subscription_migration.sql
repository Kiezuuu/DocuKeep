-- DocuKeep subscription workflow: manual payment to admin, staff activates plan.
-- Run AFTER docukeep_migration.sql in Supabase SQL Editor.

ALTER TABLE public.docukeep_entitlements
  ADD COLUMN IF NOT EXISTS billing_period text,
  ADD COLUMN IF NOT EXISTS starts_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS activated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.docukeep_entitlements
  DROP CONSTRAINT IF EXISTS docukeep_entitlements_billing_period_check;
ALTER TABLE public.docukeep_entitlements
  ADD CONSTRAINT docukeep_entitlements_billing_period_check
  CHECK (billing_period IS NULL OR billing_period IN ('week','month','year'));

CREATE TABLE IF NOT EXISTS public.docukeep_subscription_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  plan text NOT NULL DEFAULT 'premium' CHECK (plan = 'premium'),
  billing_period text NOT NULL CHECK (billing_period IN ('week','month','year')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','activated','rejected','cancelled')),
  user_note text,
  admin_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS docukeep_sub_requests_status_created_idx
  ON public.docukeep_subscription_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS docukeep_sub_requests_user_created_idx
  ON public.docukeep_subscription_requests(user_id, created_at DESC);

ALTER TABLE public.docukeep_subscription_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users create own subscription requests" ON public.docukeep_subscription_requests;
CREATE POLICY "users create own subscription requests"
  ON public.docukeep_subscription_requests FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.status = 'approved' AND p.role IN ('student','teacher')
  ));
DROP POLICY IF EXISTS "users read own subscription requests" ON public.docukeep_subscription_requests;
CREATE POLICY "users read own subscription requests"
  ON public.docukeep_subscription_requests FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_docukeep_staff());
DROP POLICY IF EXISTS "staff update subscription requests" ON public.docukeep_subscription_requests;
CREATE POLICY "staff update subscription requests"
  ON public.docukeep_subscription_requests FOR UPDATE TO authenticated
  USING (public.is_docukeep_staff()) WITH CHECK (public.is_docukeep_staff());
REVOKE DELETE ON public.docukeep_subscription_requests FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.docukeep_subscription_requests TO authenticated;

-- Staff confirms payment outside DocuKeep, then activates the selected duration.
-- Student/teacher identity role is intentionally preserved; subscription is a separate entitlement.
CREATE OR REPLACE FUNCTION public.activate_docukeep_subscription(
  p_user_id uuid,
  p_duration text,
  p_request_id uuid DEFAULT NULL,
  p_admin_note text DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_start timestamptz := now(); v_expiry timestamptz;
BEGIN
  IF NOT public.is_docukeep_staff() THEN
    RAISE EXCEPTION 'Approved staff access required.';
  END IF;
  IF p_duration NOT IN ('week','month','year') THEN
    RAISE EXCEPTION 'Choose week, month, or year.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND status = 'approved' AND role IN ('student','teacher')) THEN
    RAISE EXCEPTION 'Approved student or teacher account not found.';
  END IF;
  v_expiry := CASE p_duration
    WHEN 'week' THEN v_start + interval '7 days'
    WHEN 'month' THEN v_start + interval '1 month'
    WHEN 'year' THEN v_start + interval '1 year'
  END;

  INSERT INTO public.docukeep_entitlements
    (user_id, plan, storage_limit_bytes, active, billing_period, starts_at, expires_at, activated_by, updated_at)
  VALUES
    (p_user_id, 'premium', 137438953472, true, p_duration, v_start, v_expiry, auth.uid(), v_start)
  ON CONFLICT (user_id) DO UPDATE SET
    plan = 'premium', storage_limit_bytes = 137438953472, active = true,
    billing_period = EXCLUDED.billing_period, starts_at = EXCLUDED.starts_at,
    expires_at = EXCLUDED.expires_at, activated_by = EXCLUDED.activated_by,
    updated_at = EXCLUDED.updated_at;

  IF p_request_id IS NOT NULL THEN
    UPDATE public.docukeep_subscription_requests
       SET status = 'activated', reviewed_at = v_start, reviewed_by = auth.uid(),
           admin_note = p_admin_note
     WHERE id = p_request_id AND user_id = p_user_id AND status = 'pending';
    IF NOT FOUND THEN RAISE EXCEPTION 'Pending subscription request not found.'; END IF;
  END IF;
  RETURN v_expiry;
END;
$$;
REVOKE ALL ON FUNCTION public.activate_docukeep_subscription(uuid,text,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activate_docukeep_subscription(uuid,text,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reject_docukeep_subscription_request(
  p_request_id uuid, p_admin_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_docukeep_staff() THEN RAISE EXCEPTION 'Approved staff access required.'; END IF;
  UPDATE public.docukeep_subscription_requests
     SET status = 'rejected', reviewed_at = now(), reviewed_by = auth.uid(), admin_note = p_admin_note
   WHERE id = p_request_id AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Pending subscription request not found.'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.reject_docukeep_subscription_request(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_docukeep_subscription_request(uuid,text) TO authenticated;

-- A premium entitlement is valid only while active and before expires_at.
CREATE OR REPLACE FUNCTION public.docukeep_has_active_premium(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.docukeep_entitlements e
    WHERE e.user_id = p_user_id AND e.plan = 'premium' AND e.active = true
      AND e.expires_at IS NOT NULL AND e.expires_at > now()
  );
$$;
REVOKE ALL ON FUNCTION public.docukeep_has_active_premium(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.docukeep_has_active_premium(uuid) TO authenticated;

-- Keep the entitlement row tidy when its expiry passes. Schedule this function daily
-- with Supabase Cron if available; expiry is also checked against expires_at on every app load.
CREATE OR REPLACE FUNCTION public.expire_docukeep_subscriptions()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n integer;
BEGIN
  UPDATE public.docukeep_entitlements
     SET active = false, plan = 'free', storage_limit_bytes = 26214400, updated_at = now()
   WHERE plan = 'premium' AND active = true AND expires_at IS NOT NULL AND expires_at <= now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.expire_docukeep_subscriptions() FROM PUBLIC, anon, authenticated;

-- Enforce total per-user document storage at the database layer, not just in JavaScript.
CREATE OR REPLACE FUNCTION public.enforce_docukeep_storage_quota()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_limit bigint; v_used bigint; v_is_premium boolean;
BEGIN
  SELECT (e.plan = 'premium' AND e.active = true AND e.expires_at > now()),
         CASE WHEN e.plan = 'premium' AND e.active = true AND e.expires_at > now()
              THEN e.storage_limit_bytes ELSE 26214400 END
    INTO v_is_premium, v_limit
    FROM public.docukeep_entitlements e WHERE e.user_id = NEW.owner_id;
  IF NOT FOUND THEN v_limit := 26214400; END IF;
  SELECT COALESCE(sum(d.size_bytes),0) INTO v_used
    FROM public.documents d
   WHERE d.owner_id = NEW.owner_id AND d.id <> NEW.id;
  IF v_used + COALESCE(NEW.size_bytes,0) > v_limit THEN
    RAISE EXCEPTION 'Storage quota exceeded. Your current limit is % bytes.', v_limit;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS docukeep_storage_quota_guard ON public.documents;
CREATE TRIGGER docukeep_storage_quota_guard
BEFORE INSERT OR UPDATE OF owner_id, size_bytes ON public.documents
FOR EACH ROW EXECUTE FUNCTION public.enforce_docukeep_storage_quota();

-- Note: the Supabase project/bucket itself must have enough provider storage capacity
-- for 128 GB. The per-file upload ceiling remains the existing 25 MB setting.

-- PREMIUM-ONLY FEATURE ENFORCEMENT
-- The six advertised Premium features are restricted to active, unexpired subscriptions.

-- Bulk upload marker: single-file uploads remain available on Free; batches require Premium.
ALTER TABLE public.documents ADD COLUMN IF NOT EXISTS upload_batch_id uuid;
CREATE OR REPLACE FUNCTION public.enforce_docukeep_premium_features()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_TABLE_NAME = 'documents' AND TG_OP IN ('INSERT','UPDATE') THEN
    IF NEW.upload_batch_id IS NOT NULL AND NOT public.docukeep_has_active_premium(NEW.owner_id) THEN
      RAISE EXCEPTION 'Bulk upload is a Premium-only feature.';
    END IF;
    RETURN NEW;
  ELSIF TG_TABLE_NAME = 'docukeep_folders' AND TG_OP IN ('INSERT','UPDATE') THEN
    IF NEW.color IS DISTINCT FROM '#2862a5' AND NOT public.docukeep_has_active_premium(NEW.owner_id) THEN
      RAISE EXCEPTION 'Custom folder colors are a Premium-only feature.';
    END IF;
    RETURN NEW;
  ELSIF TG_TABLE_NAME = 'documents' AND TG_OP = 'DELETE' THEN
    IF auth.uid() = OLD.owner_id AND OLD.sha256 IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.documents d WHERE d.owner_id = OLD.owner_id AND d.sha256 = OLD.sha256 AND d.id <> OLD.id)
       AND NOT public.docukeep_has_active_premium(OLD.owner_id) THEN
      RAISE EXCEPTION 'Deleting duplicate files is a Premium-only feature.';
    END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
DROP TRIGGER IF EXISTS docukeep_premium_bulk_upload_guard ON public.documents;
CREATE TRIGGER docukeep_premium_bulk_upload_guard
BEFORE INSERT OR UPDATE OF upload_batch_id ON public.documents
FOR EACH ROW EXECUTE FUNCTION public.enforce_docukeep_premium_features();
DROP TRIGGER IF EXISTS docukeep_premium_duplicate_delete_guard ON public.documents;
CREATE TRIGGER docukeep_premium_duplicate_delete_guard
BEFORE DELETE ON public.documents
FOR EACH ROW EXECUTE FUNCTION public.enforce_docukeep_premium_features();
DROP TRIGGER IF EXISTS docukeep_premium_folder_color_guard ON public.docukeep_folders;
CREATE TRIGGER docukeep_premium_folder_color_guard
BEFORE INSERT OR UPDATE OF color ON public.docukeep_folders
FOR EACH ROW EXECUTE FUNCTION public.enforce_docukeep_premium_features();

-- Group creation, membership, and document sharing require active Premium for both
-- the person sharing and each individual receiving access.
DROP POLICY IF EXISTS "group members read" ON public.docukeep_groups;
DROP POLICY IF EXISTS "group owner create" ON public.docukeep_groups;
DROP POLICY IF EXISTS "group owner update" ON public.docukeep_groups;
CREATE POLICY "premium group members read" ON public.docukeep_groups FOR SELECT TO authenticated
USING (public.is_docukeep_staff() OR (public.docukeep_has_active_premium(auth.uid()) AND (created_by=auth.uid() OR public.docukeep_is_group_member(id,auth.uid()))));
CREATE POLICY "premium group owner create" ON public.docukeep_groups FOR INSERT TO authenticated
WITH CHECK (created_by=auth.uid() AND public.docukeep_has_active_premium(auth.uid()));
CREATE POLICY "premium group owner update" ON public.docukeep_groups FOR UPDATE TO authenticated
USING (public.is_docukeep_staff() OR (created_by=auth.uid() AND public.docukeep_has_active_premium(auth.uid())))
WITH CHECK (public.is_docukeep_staff() OR (created_by=auth.uid() AND public.docukeep_has_active_premium(auth.uid())));
DROP POLICY IF EXISTS "group creator manages members" ON public.docukeep_group_members;
CREATE POLICY "premium group creator manages members" ON public.docukeep_group_members FOR ALL TO authenticated
USING (public.is_docukeep_staff() OR (public.docukeep_is_group_owner(group_id,auth.uid()) AND public.docukeep_has_active_premium(auth.uid())))
WITH CHECK (public.is_docukeep_staff() OR (public.docukeep_is_group_owner(group_id,auth.uid()) AND public.docukeep_has_active_premium(auth.uid()) AND public.docukeep_has_active_premium(user_id)));
DROP POLICY IF EXISTS "document access read" ON public.docukeep_document_access;
CREATE POLICY "premium document access read" ON public.docukeep_document_access FOR SELECT TO authenticated
USING (public.is_docukeep_staff() OR (public.docukeep_has_active_premium(auth.uid()) AND public.docukeep_can_read_document(document_id,auth.uid())));
DROP POLICY IF EXISTS "document owner manages access" ON public.docukeep_document_access;
CREATE POLICY "premium document owner manages access" ON public.docukeep_document_access FOR ALL TO authenticated
USING (public.is_docukeep_staff() OR (EXISTS (SELECT 1 FROM public.documents d WHERE d.id=document_id AND d.owner_id=auth.uid()) AND public.docukeep_has_active_premium(auth.uid())))
WITH CHECK (public.is_docukeep_staff() OR (
  EXISTS (SELECT 1 FROM public.documents d WHERE d.id=document_id AND d.owner_id=auth.uid())
  AND public.docukeep_has_active_premium(auth.uid())
  AND (user_id IS NULL OR public.docukeep_has_active_premium(user_id))
  AND (group_id IS NULL OR EXISTS (SELECT 1 FROM public.docukeep_groups g WHERE g.id=group_id AND g.created_by=auth.uid()))
));
DROP POLICY IF EXISTS "shared documents read" ON storage.objects;
CREATE POLICY "premium shared documents read" ON storage.objects FOR SELECT TO authenticated USING (
  bucket_id='docukeep-files' AND public.docukeep_has_active_premium(auth.uid()) AND EXISTS (
    SELECT 1 FROM public.documents d JOIN public.docukeep_document_access a ON a.document_id=d.id
    WHERE d.storage_path=name AND public.docukeep_has_active_premium(d.owner_id)
      AND (a.user_id=auth.uid() OR (a.group_id IS NOT NULL AND public.docukeep_is_group_member(a.group_id,auth.uid())))
  )
);

-- Staff can still administer groups and subscriptions through existing staff-only rules.

-- Ensure shared document metadata is also unavailable to non-Premium recipients.
CREATE OR REPLACE FUNCTION public.docukeep_can_read_document(p_document_id uuid,p_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT EXISTS (SELECT 1 FROM public.documents d WHERE d.id=p_document_id AND d.owner_id=p_user_id)
  OR EXISTS (
    SELECT 1 FROM public.documents d JOIN public.docukeep_document_access a ON a.document_id=d.id
    WHERE d.id=p_document_id AND public.docukeep_has_active_premium(d.owner_id)
      AND public.docukeep_has_active_premium(p_user_id)
      AND (a.user_id=p_user_id OR (a.group_id IS NOT NULL AND public.docukeep_is_group_member(a.group_id,p_user_id)))
  );
$$;
DROP POLICY IF EXISTS "members own read" ON public.docukeep_group_members;
CREATE POLICY "premium members own read" ON public.docukeep_group_members FOR SELECT TO authenticated
USING (public.is_docukeep_staff() OR (public.docukeep_has_active_premium(auth.uid()) AND (user_id=auth.uid() OR public.docukeep_is_group_owner(group_id,auth.uid()))));
