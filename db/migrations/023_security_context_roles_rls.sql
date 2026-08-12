DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'themis_app') THEN
        CREATE ROLE themis_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'themis_worker') THEN
        CREATE ROLE themis_worker NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'themis_admin') THEN
        CREATE ROLE themis_admin NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT BYPASSRLS;
    END IF;
END;
$$;

ALTER ROLE themis_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
ALTER ROLE themis_worker NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
ALTER ROLE themis_admin NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT BYPASSRLS;

ALTER ROLE themis_app SET search_path = pg_catalog, public;
ALTER ROLE themis_app SET row_security = on;
ALTER ROLE themis_worker SET search_path = pg_catalog, public;
ALTER ROLE themis_worker SET row_security = on;
ALTER ROLE themis_admin SET search_path = pg_catalog, public;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE FUNCTION app_current_user_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    raw_value text;
BEGIN
    raw_value := nullif(current_setting('app.user_id', true), '');
    IF raw_value IS NULL THEN RETURN NULL; END IF;
    RETURN raw_value::uuid;
EXCEPTION WHEN invalid_text_representation THEN
    RETURN NULL;
END;
$$;

CREATE FUNCTION app_current_organization_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    raw_value text;
BEGIN
    raw_value := nullif(current_setting('app.organization_id', true), '');
    IF raw_value IS NULL THEN RETURN NULL; END IF;
    RETURN raw_value::uuid;
EXCEPTION WHEN invalid_text_representation THEN
    RETURN NULL;
END;
$$;

CREATE FUNCTION app_tenant_access_allowed(target_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT target_organization_id IS NOT NULL
       AND target_organization_id = public.app_current_organization_id()
       AND public.app_current_user_id() IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM public.organization_members member_record
           WHERE member_record.organization_id = target_organization_id
             AND member_record.user_id = public.app_current_user_id()
             AND member_record.status = 'ACTIVE'
       );
$$;

CREATE FUNCTION app_finding_citation_access_allowed(target_finding_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.findings finding_record
        WHERE finding_record.id = target_finding_id
          AND public.app_tenant_access_allowed(finding_record.organization_id)
    );
$$;

CREATE FUNCTION app_audit_change_access_allowed(target_audit_log_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.audit_logs audit_record
        WHERE audit_record.id = target_audit_log_id
          AND audit_record.organization_id IS NOT NULL
          AND public.app_tenant_access_allowed(audit_record.organization_id)
    );
$$;

CREATE FUNCTION record_audit_event(
    target_organization_id uuid,
    target_user_id uuid,
    target_category text,
    target_action text,
    target_result text,
    target_source text,
    target_entity_type text DEFAULT NULL,
    target_entity_id uuid DEFAULT NULL,
    target_request_id uuid DEFAULT NULL,
    target_trace_id text DEFAULT NULL,
    target_ip_address inet DEFAULT NULL,
    target_user_agent text DEFAULT NULL,
    target_metadata jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    audit_id_value uuid;
BEGIN
    IF target_source NOT IN ('USER', 'API') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'application audit source must be USER or API';
    END IF;
    IF target_organization_id IS NOT NULL THEN
        IF NOT public.app_tenant_access_allowed(target_organization_id) THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'audit organization context is not authorized';
        END IF;
        IF target_user_id IS DISTINCT FROM public.app_current_user_id() THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'audit actor must match the authenticated context';
        END IF;
    ELSIF target_user_id IS NULL OR target_user_id IS DISTINCT FROM public.app_current_user_id() THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'global user audit requires matching authenticated context';
    END IF;

    INSERT INTO public.audit_logs(
        organization_id, user_id, category, action, entity_type, entity_id,
        result, request_id, trace_id, ip_address, user_agent, source, metadata
    ) VALUES (
        target_organization_id, target_user_id, target_category, target_action,
        target_entity_type, target_entity_id, target_result, target_request_id,
        target_trace_id, target_ip_address, target_user_agent, target_source, target_metadata
    ) RETURNING id INTO audit_id_value;
    RETURN audit_id_value;
END;
$$;

CREATE FUNCTION record_system_audit_event(
    target_organization_id uuid,
    target_category text,
    target_action text,
    target_result text,
    target_source text,
    target_entity_type text DEFAULT NULL,
    target_entity_id uuid DEFAULT NULL,
    target_metadata jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    audit_id_value uuid;
BEGIN
    IF target_source NOT IN ('WORKER', 'RULE_ENGINE', 'AI', 'SYSTEM', 'SYSTEM_ADMIN') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'system audit source is not privileged';
    END IF;
    INSERT INTO public.audit_logs(
        organization_id, category, action, entity_type, entity_id,
        result, source, metadata
    ) VALUES (
        target_organization_id, target_category, target_action,
        target_entity_type, target_entity_id, target_result, target_source, target_metadata
    ) RETURNING id INTO audit_id_value;
    RETURN audit_id_value;
END;
$$;

CREATE FUNCTION record_audit_log_change(
    target_audit_log_id uuid,
    target_field_name text,
    target_old_value jsonb,
    target_new_value jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    change_id_value uuid;
BEGIN
    IF NOT public.app_audit_change_access_allowed(target_audit_log_id) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'audit event is outside the authorized tenant context';
    END IF;
    INSERT INTO public.audit_log_changes(audit_log_id, field_name, old_value, new_value)
    VALUES (target_audit_log_id, target_field_name, target_old_value, target_new_value)
    RETURNING id INTO change_id_value;
    RETURN change_id_value;
END;
$$;

CREATE FUNCTION record_data_access(
    target_organization_id uuid,
    target_user_id uuid,
    target_resource_type text,
    target_resource_id uuid,
    target_access_type text,
    target_request_id uuid DEFAULT NULL,
    target_ip_address inet DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    access_id_value uuid;
BEGIN
    IF NOT public.app_tenant_access_allowed(target_organization_id)
       OR target_user_id IS DISTINCT FROM public.app_current_user_id() THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'data access actor or tenant context is not authorized';
    END IF;
    INSERT INTO public.data_access_logs(
        organization_id, user_id, resource_type, resource_id,
        access_type, request_id, ip_address
    ) VALUES (
        target_organization_id, target_user_id, target_resource_type,
        target_resource_id, target_access_type, target_request_id, target_ip_address
    ) RETURNING id INTO access_id_value;
    RETURN access_id_value;
END;
$$;

REVOKE EXECUTE ON FUNCTION app_current_user_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION app_current_organization_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION app_tenant_access_allowed(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION app_finding_citation_access_allowed(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION app_audit_change_access_allowed(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION record_audit_event(
    uuid, uuid, text, text, text, text, text, uuid, uuid, text, inet, text, jsonb
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION record_audit_log_change(uuid, text, jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION record_data_access(uuid, uuid, text, uuid, text, uuid, inet) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION record_system_audit_event(
    uuid, text, text, text, text, text, uuid, jsonb
) FROM PUBLIC;

ALTER FUNCTION user_has_organization_permission(uuid, uuid, text)
    SECURITY DEFINER SET search_path = pg_catalog, public;

CREATE INDEX idx_organization_members_user_organization_status
    ON organization_members(user_id, organization_id, status);
CREATE INDEX idx_organization_members_organization_user_status
    ON organization_members(organization_id, user_id, status);

DO $$
DECLARE
    table_name_value text;
BEGIN
    FOREACH table_name_value IN ARRAY ARRAY[
        'organization_members', 'organization_member_roles',
        'export_batches', 'export_batch_items',
        'organization_registered_entities', 'batch_registered_entities',
        'documents', 'document_revisions', 'document_files', 'batch_documents',
        'document_extraction_jobs', 'extracted_fields', 'lab_test_results',
        'document_verifications', 'document_verification_changes',
        'compliance_checks', 'compliance_check_documents',
        'compliance_check_legal_versions', 'rule_executions', 'findings',
        'compliance_check_events', 'ai_runs',
        'compliance_reports', 'report_findings', 'report_finding_citations',
        'report_approvals', 'remediation_tasks', 'remediation_task_assignees',
        'remediation_evidence', 'remediation_reviews', 'remediation_task_events',
        'batch_legal_impacts', 'alerts', 'alert_recipients', 'notifications',
        'audit_logs', 'data_access_logs'
    ] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name_value);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON public.%I TO themis_app USING (public.app_tenant_access_allowed(organization_id)) WITH CHECK (public.app_tenant_access_allowed(organization_id))',
            table_name_value
        );
    END LOOP;
END;
$$;

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON organizations TO themis_app
    USING (public.app_tenant_access_allowed(id))
    WITH CHECK (public.app_tenant_access_allowed(id));

ALTER TABLE finding_citations ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON finding_citations TO themis_app
    USING (public.app_finding_citation_access_allowed(finding_id))
    WITH CHECK (public.app_finding_citation_access_allowed(finding_id));

ALTER TABLE audit_log_changes ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON audit_log_changes TO themis_app
    USING (public.app_audit_change_access_allowed(audit_log_id))
    WITH CHECK (public.app_audit_change_access_allowed(audit_log_id));

ALTER TABLE system_job_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_job_read ON system_job_runs FOR SELECT TO themis_app
    USING (organization_id IS NOT NULL AND public.app_tenant_access_allowed(organization_id));
CREATE POLICY worker_job_access ON system_job_runs TO themis_worker
    USING (true) WITH CHECK (true);

GRANT USAGE ON SCHEMA public TO themis_app, themis_worker, themis_admin;

GRANT SELECT, INSERT, UPDATE, DELETE ON
    organizations, organization_members, organization_member_roles,
    export_batches, export_batch_items,
    organization_registered_entities, batch_registered_entities,
    documents, document_revisions, document_files, batch_documents,
    document_extraction_jobs, extracted_fields, lab_test_results,
    document_verifications, document_verification_changes,
    compliance_checks, compliance_check_documents, compliance_check_legal_versions,
    rule_executions, findings, finding_citations, compliance_check_events, ai_runs,
    compliance_reports, report_findings, report_finding_citations, report_approvals,
    remediation_tasks, remediation_task_assignees, remediation_evidence,
    remediation_reviews, remediation_task_events,
    batch_legal_impacts, alerts, alert_recipients, notifications
TO themis_app;

GRANT SELECT ON audit_logs, audit_log_changes, data_access_logs, system_job_runs TO themis_app;

GRANT SELECT ON
    roles, permissions, role_permissions, document_types,
    countries, markets, products, product_varieties, product_forms,
    hs_nomenclatures, hs_codes, product_hs_codes,
    registered_export_entities, measurement_dimensions, measurement_units,
    legal_sources, legal_authorities, legal_documents, legal_document_parties,
    legal_document_versions, legal_document_files, legal_sections,
    legal_requirements, requirement_scopes, requirement_parameters,
    regulated_substances, legal_limits, legal_citations, market_entity_approvals,
    legal_chunks, legal_embeddings, compliance_rules, compliance_rule_versions,
    regulation_changes, regulation_change_items
TO themis_app;

GRANT SELECT, INSERT, UPDATE ON system_job_runs TO themis_worker;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO themis_admin;

GRANT EXECUTE ON FUNCTION app_current_user_id() TO themis_app, themis_worker, themis_admin;
GRANT EXECUTE ON FUNCTION app_current_organization_id() TO themis_app, themis_worker, themis_admin;
GRANT EXECUTE ON FUNCTION app_tenant_access_allowed(uuid) TO themis_app, themis_worker, themis_admin;
GRANT EXECUTE ON FUNCTION app_finding_citation_access_allowed(uuid) TO themis_app, themis_admin;
GRANT EXECUTE ON FUNCTION app_audit_change_access_allowed(uuid) TO themis_app, themis_admin;
GRANT EXECUTE ON FUNCTION user_has_organization_permission(uuid, uuid, text)
    TO themis_app, themis_admin;
GRANT EXECUTE ON FUNCTION record_audit_event(
    uuid, uuid, text, text, text, text, text, uuid, uuid, text, inet, text, jsonb
) TO themis_app, themis_admin;
GRANT EXECUTE ON FUNCTION record_audit_log_change(uuid, text, jsonb, jsonb)
    TO themis_app, themis_admin;
GRANT EXECUTE ON FUNCTION record_data_access(uuid, uuid, text, uuid, text, uuid, inet)
    TO themis_app, themis_admin;
GRANT EXECUTE ON FUNCTION record_system_audit_event(
    uuid, text, text, text, text, text, uuid, jsonb
) TO themis_worker, themis_admin;

GRANT EXECUTE ON FUNCTION retrieve_legal_chunks_for_check(uuid, uuid, vector, text, integer)
    TO themis_app;
GRANT EXECUTE ON FUNCTION generate_compliance_report(uuid, uuid, uuid, text, text, text)
    TO themis_app;
GRANT EXECUTE ON FUNCTION submit_compliance_report(uuid, uuid, uuid)
    TO themis_app;
GRANT EXECUTE ON FUNCTION decide_compliance_report(uuid, uuid, uuid, text, text)
    TO themis_app;
GRANT EXECUTE ON FUNCTION return_rejected_report_to_draft(uuid, uuid, uuid)
    TO themis_app;
GRANT EXECUTE ON FUNCTION create_remediation_task(uuid, uuid, uuid, text, text, text, date, uuid)
    TO themis_app;
GRANT EXECUTE ON FUNCTION assign_remediation_task(uuid, uuid, uuid, uuid)
    TO themis_app;
GRANT EXECUTE ON FUNCTION start_remediation_task(uuid, uuid, uuid)
    TO themis_app;
GRANT EXECUTE ON FUNCTION submit_remediation_evidence(uuid, uuid, uuid, uuid, uuid, uuid, text)
    TO themis_app;
GRANT EXECUTE ON FUNCTION decide_remediation_evidence(uuid, uuid, uuid, text)
    TO themis_app;
GRANT EXECUTE ON FUNCTION review_remediation_task(uuid, uuid, uuid, text, text)
    TO themis_app;
GRANT EXECUTE ON FUNCTION create_recheck_for_report(uuid, uuid, uuid, text)
    TO themis_app;
GRANT EXECUTE ON FUNCTION compare_legal_versions(uuid, uuid) TO themis_admin;
GRANT EXECUTE ON FUNCTION confirm_regulation_change(uuid, uuid, text) TO themis_admin;
GRANT EXECUTE ON FUNCTION acknowledge_alert(uuid, uuid, uuid) TO themis_app;
