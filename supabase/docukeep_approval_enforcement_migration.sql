-- DocuKeep approval enforcement (additive, backward-compatible)
-- Run after docukeep_migration.sql and the existing role/account-notification migrations.
-- Approved staff already satisfy docukeep_is_approved_user(); existing accounts are unchanged.
-- Pending/rejected users may still read their own profile row so the UI can explain their status,
-- but cannot directly query document, folder, sharing, or subscription data through Supabase.

DO $$
DECLARE
  table_name text;
  protected_tables text[] := ARRAY[
    'documents',
    'docukeep_folders',
    'docukeep_groups',
    'docukeep_group_members',
    'docukeep_document_access',
    'docukeep_upload_sync',
    'docukeep_subscription_requests',
    'docukeep_profile_files',
    'docukeep_onboarding_progress'
  ];
BEGIN
  FOREACH table_name IN ARRAY protected_tables LOOP
    IF to_regclass(format('public.%I', table_name)) IS NOT NULL THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'approved_account_required_' || table_name, table_name);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (public.docukeep_is_approved_user()) WITH CHECK (public.docukeep_is_approved_user())',
        'approved_account_required_' || table_name,
        table_name
      );
    END IF;
  END LOOP;
END $$;

-- Private file reads and writes are subject to the same approval gate.
DROP POLICY IF EXISTS approved_account_required_docukeep_files ON storage.objects;
CREATE POLICY approved_account_required_docukeep_files
ON storage.objects AS RESTRICTIVE
FOR ALL TO authenticated
USING (bucket_id <> 'docukeep-files' OR public.docukeep_is_approved_user())
WITH CHECK (bucket_id <> 'docukeep-files' OR public.docukeep_is_approved_user());

NOTIFY pgrst, 'reload schema';
