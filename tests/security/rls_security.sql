BEGIN;

INSERT INTO users(id, email, full_name, status) VALUES
    ('10000000-0000-0000-0000-000000000001', 'rls-a@example.com', 'RLS User A', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000002', 'rls-b@example.com', 'RLS User B', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000003', 'rls-outsider@example.com', 'RLS Outsider', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000004', 'rls-suspended@example.com', 'RLS Suspended', 'ACTIVE'),
    ('10000000-0000-0000-0000-000000000005', 'rls-removed@example.com', 'RLS Removed', 'ACTIVE');

INSERT INTO organizations(id, name, created_by) VALUES
    ('20000000-0000-0000-0000-000000000001', 'RLS Organization A', '10000000-0000-0000-0000-000000000001'),
    ('20000000-0000-0000-0000-000000000002', 'RLS Organization B', '10000000-0000-0000-0000-000000000002');

INSERT INTO organization_members(id, organization_id, user_id, status, joined_at) VALUES
    ('21000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'ACTIVE', now()),
    ('21000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'ACTIVE', now()),
    ('21000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000004', 'SUSPENDED', NULL),
    ('21000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000005', 'REMOVED', NULL);

INSERT INTO export_batches(
    id, organization_id, batch_code, origin_country_id, destination_country_id,
    market_id, planned_export_date, created_by
) SELECT
    fixture.id, fixture.organization_id, fixture.batch_code,
    vn.id, cn.id, market_record.id, DATE '2028-01-01', fixture.created_by
FROM (VALUES
    ('30000000-0000-0000-0000-000000000001'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, 'RLS-BATCH-A', '10000000-0000-0000-0000-000000000001'::uuid),
    ('30000000-0000-0000-0000-000000000002'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, 'RLS-BATCH-B', '10000000-0000-0000-0000-000000000002'::uuid)
) fixture(id, organization_id, batch_code, created_by)
CROSS JOIN countries vn
CROSS JOIN countries cn
CROSS JOIN markets market_record
WHERE vn.iso2_code = 'VN' AND cn.iso2_code = 'CN' AND market_record.code = 'CN_GACC';

INSERT INTO documents(id, organization_id, document_type_id, title, created_by)
SELECT fixture.id, fixture.organization_id, type_record.id, fixture.title, fixture.created_by
FROM (VALUES
    ('40000000-0000-0000-0000-000000000001'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, 'RLS Document A', '10000000-0000-0000-0000-000000000001'::uuid),
    ('40000000-0000-0000-0000-000000000002'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, 'RLS Document B', '10000000-0000-0000-0000-000000000002'::uuid)
) fixture(id, organization_id, title, created_by)
CROSS JOIN document_types type_record
WHERE type_record.code = 'LAB_REPORT';

INSERT INTO compliance_checks(
    id, organization_id, batch_id, market_id, created_by, check_number
) SELECT
    fixture.id, fixture.organization_id, fixture.batch_id, market_record.id,
    fixture.created_by, 1
FROM (VALUES
    ('50000000-0000-0000-0000-000000000001'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, '30000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000001'::uuid),
    ('50000000-0000-0000-0000-000000000002'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, '30000000-0000-0000-0000-000000000002'::uuid, '10000000-0000-0000-0000-000000000002'::uuid)
) fixture(id, organization_id, batch_id, created_by)
CROSS JOIN markets market_record
WHERE market_record.code = 'CN_GACC';

INSERT INTO findings(
    id, organization_id, check_id, source_type, finding_type,
    title, description, severity, validation_status
) VALUES
    ('51000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'MANUAL', 'RLS_TEST', 'RLS Finding A', 'RLS fixture A', 'LOW', 'MANUAL_REVIEW_REQUIRED'),
    ('51000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000002', 'MANUAL', 'RLS_TEST', 'RLS Finding B', 'RLS fixture B', 'LOW', 'MANUAL_REVIEW_REQUIRED');

ALTER TABLE compliance_reports DISABLE TRIGGER trg_validate_compliance_report;
INSERT INTO compliance_reports(
    id, organization_id, check_id, batch_id, version_number,
    report_code, overall_result, title, generated_by
) VALUES
    ('60000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 1, 'RLS-REPORT-A', 'COMPLIANT', 'RLS Report A', '10000000-0000-0000-0000-000000000001'),
    ('60000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 1, 'RLS-REPORT-B', 'COMPLIANT', 'RLS Report B', '10000000-0000-0000-0000-000000000002');
ALTER TABLE compliance_reports ENABLE TRIGGER trg_validate_compliance_report;

INSERT INTO report_findings(
    id, organization_id, check_id, report_id, finding_id, display_order,
    source_type_snapshot, finding_type_snapshot, title_snapshot,
    description_snapshot, severity_snapshot, validation_status_snapshot
) VALUES
    ('61000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', 1, 'MANUAL', 'RLS_TEST', 'RLS Finding A', 'RLS fixture A', 'LOW', 'MANUAL_REVIEW_REQUIRED'),
    ('61000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000002', 1, 'MANUAL', 'RLS_TEST', 'RLS Finding B', 'RLS fixture B', 'LOW', 'MANUAL_REVIEW_REQUIRED');

ALTER TABLE remediation_tasks DISABLE TRIGGER trg_validate_remediation_task;
INSERT INTO remediation_tasks(
    id, organization_id, batch_id, report_id, finding_id,
    title, priority, created_by
) VALUES
    ('62000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001', 'RLS Remediation A', 'LOW', '10000000-0000-0000-0000-000000000001'),
    ('62000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000002', 'RLS Remediation B', 'LOW', '10000000-0000-0000-0000-000000000002');
ALTER TABLE remediation_tasks ENABLE TRIGGER trg_validate_remediation_task;

INSERT INTO alerts(
    id, organization_id, alert_type, severity, title, message
) VALUES
    ('70000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'SYSTEM', 'INFO', 'RLS Alert A', 'RLS fixture A'),
    ('70000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'SYSTEM', 'INFO', 'RLS Alert B', 'RLS fixture B');
INSERT INTO notifications(
    id, organization_id, user_id, alert_id, channel, title, message, idempotency_key
) VALUES
    ('71000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'IN_APP', 'RLS Notification A', 'RLS fixture A', 'RLS-NOTIFICATION-A'),
    ('71000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000002', 'IN_APP', 'RLS Notification B', 'RLS fixture B', 'RLS-NOTIFICATION-B');

INSERT INTO system_job_runs(id, job_type, organization_id, idempotency_key) VALUES
    ('80000000-0000-0000-0000-000000000001', 'OCR', '20000000-0000-0000-0000-000000000001', 'RLS-JOB-A'),
    ('80000000-0000-0000-0000-000000000002', 'OCR', '20000000-0000-0000-0000-000000000002', 'RLS-JOB-B'),
    ('80000000-0000-0000-0000-000000000003', 'NOTIFICATION_DELIVERY', NULL, 'RLS-JOB-GLOBAL');

DO $$
DECLARE
    table_name_value text;
BEGIN
    FOREACH table_name_value IN ARRAY ARRAY[
        'organizations', 'organization_members', 'organization_member_roles',
        'export_batches', 'export_batch_items', 'organization_registered_entities',
        'batch_registered_entities', 'documents', 'document_revisions', 'document_files',
        'batch_documents', 'document_extraction_jobs', 'extracted_fields', 'lab_test_results',
        'document_verifications', 'document_verification_changes', 'compliance_checks',
        'compliance_check_documents', 'compliance_check_legal_versions', 'rule_executions',
        'findings', 'finding_citations', 'compliance_check_events', 'ai_runs',
        'compliance_reports', 'report_findings', 'report_finding_citations', 'report_approvals',
        'remediation_tasks', 'remediation_task_assignees', 'remediation_evidence',
        'remediation_reviews', 'remediation_task_events', 'batch_legal_impacts', 'alerts',
        'alert_recipients', 'notifications', 'audit_logs', 'audit_log_changes',
        'data_access_logs', 'system_job_runs'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_class class_record
            JOIN pg_namespace namespace_record ON namespace_record.oid = class_record.relnamespace
            WHERE namespace_record.nspname = 'public'
              AND class_record.relname = table_name_value
              AND class_record.relrowsecurity
        ) THEN
            RAISE EXCEPTION 'RLS is not enabled on %', table_name_value;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname IN ('themis_app', 'themis_worker')
          AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls OR rolcanlogin)
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'themis_admin' AND rolbypassrls AND NOT rolcanlogin
    ) THEN
        RAISE EXCEPTION 'Logical database role attributes are unsafe';
    END IF;
    IF has_schema_privilege('themis_app', 'public', 'CREATE')
       OR EXISTS (
           SELECT 1 FROM pg_class class_record
           JOIN pg_roles role_record ON role_record.oid = class_record.relowner
           WHERE class_record.relname = 'export_batches' AND role_record.rolname = 'themis_app'
       ) THEN
        RAISE EXCEPTION 'Application role owns schema objects or can create in public';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc procedure_record
        WHERE procedure_record.proname = 'app_tenant_access_allowed'
          AND procedure_record.prosecdef
          AND procedure_record.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
    ) THEN
        RAISE EXCEPTION 'Tenant helper is not a fixed-search-path security definer';
    END IF;
END $$;

SELECT set_config('app.user_id', '10000000-0000-0000-0000-000000000001', true);
SELECT set_config('app.organization_id', '20000000-0000-0000-0000-000000000001', true);
SET LOCAL ROLE themis_app;

DO $$
DECLARE
    row_count integer;
    audit_id_value uuid;
BEGIN
    SELECT count(*) INTO row_count FROM export_batches;
    IF row_count <> 1 OR NOT EXISTS (
        SELECT 1 FROM export_batches WHERE id = '30000000-0000-0000-0000-000000000001'
    ) THEN RAISE EXCEPTION 'Active member cannot read only its own batch'; END IF;
    IF EXISTS (SELECT 1 FROM export_batches WHERE id = '30000000-0000-0000-0000-000000000002')
       OR EXISTS (SELECT 1 FROM documents WHERE id = '40000000-0000-0000-0000-000000000002')
       OR EXISTS (SELECT 1 FROM findings WHERE id = '51000000-0000-0000-0000-000000000002')
       OR EXISTS (SELECT 1 FROM compliance_reports WHERE id = '60000000-0000-0000-0000-000000000002')
       OR EXISTS (SELECT 1 FROM remediation_tasks WHERE id = '62000000-0000-0000-0000-000000000002')
       OR EXISTS (SELECT 1 FROM alerts WHERE id = '70000000-0000-0000-0000-000000000002')
       OR EXISTS (SELECT 1 FROM notifications WHERE id = '71000000-0000-0000-0000-000000000002') THEN
        RAISE EXCEPTION 'Cross-tenant read leaked a protected row';
    END IF;
    IF (SELECT count(*) FROM system_job_runs) <> 1 THEN
        RAISE EXCEPTION 'Application job visibility crossed tenant or global boundary';
    END IF;

    BEGIN
        INSERT INTO export_batches(
            organization_id, batch_code, origin_country_id, destination_country_id,
            market_id, created_by
        ) SELECT
            '20000000-0000-0000-0000-000000000002', 'RLS-FORBIDDEN-BATCH',
            vn.id, cn.id, market_record.id, '10000000-0000-0000-0000-000000000001'
        FROM countries vn, countries cn, markets market_record
        WHERE vn.iso2_code = 'VN' AND cn.iso2_code = 'CN' AND market_record.code = 'CN_GACC';
        RAISE EXCEPTION 'Cross-tenant batch insert was accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        INSERT INTO batch_documents(organization_id, batch_id, document_id, attached_by)
        VALUES (
            '20000000-0000-0000-0000-000000000002',
            '30000000-0000-0000-0000-000000000002',
            '40000000-0000-0000-0000-000000000002',
            '10000000-0000-0000-0000-000000000001'
        );
        RAISE EXCEPTION 'Cross-tenant document attachment was accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    UPDATE export_batches SET notes = 'forbidden' WHERE id = '30000000-0000-0000-0000-000000000002';
    GET DIAGNOSTICS row_count = ROW_COUNT;
    IF row_count <> 0 THEN RAISE EXCEPTION 'Cross-tenant update changed a row'; END IF;
    DELETE FROM export_batches WHERE id = '30000000-0000-0000-0000-000000000002';
    GET DIAGNOSTICS row_count = ROW_COUNT;
    IF row_count <> 0 THEN RAISE EXCEPTION 'Cross-tenant delete changed a row'; END IF;

    BEGIN
        INSERT INTO batch_documents(organization_id, batch_id, document_id, attached_by)
        VALUES (
            '20000000-0000-0000-0000-000000000001',
            '30000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-000000000002',
            '10000000-0000-0000-0000-000000000001'
        );
        RAISE EXCEPTION 'RLS masked a cross-tenant composite-FK defect';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    PERFORM set_config('app.user_id', '', true);
    IF EXISTS (SELECT 1 FROM export_batches) THEN RAISE EXCEPTION 'Missing user context did not fail closed'; END IF;
    PERFORM set_config('app.user_id', 'not-a-uuid', true);
    IF app_current_user_id() IS NOT NULL OR EXISTS (SELECT 1 FROM export_batches) THEN
        RAISE EXCEPTION 'Malformed user context leaked tenant rows';
    END IF;
    PERFORM set_config('app.user_id', '10000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.organization_id', '', true);
    IF EXISTS (SELECT 1 FROM export_batches) THEN RAISE EXCEPTION 'Missing organization context did not fail closed'; END IF;
    PERFORM set_config('app.organization_id', 'malformed', true);
    IF app_current_organization_id() IS NOT NULL OR EXISTS (SELECT 1 FROM export_batches) THEN
        RAISE EXCEPTION 'Malformed organization context leaked tenant rows';
    END IF;
    PERFORM set_config('app.organization_id', '20000000-0000-0000-0000-000000000002', true);
    IF EXISTS (SELECT 1 FROM export_batches) THEN RAISE EXCEPTION 'Organization context switch bypassed membership'; END IF;
    PERFORM set_config('app.organization_id', '20000000-0000-0000-0000-000000000001', true);
    PERFORM set_config('app.user_id', '10000000-0000-0000-0000-000000000003', true);
    IF EXISTS (SELECT 1 FROM export_batches) THEN RAISE EXCEPTION 'Non-member read tenant data'; END IF;
    PERFORM set_config('app.user_id', '10000000-0000-0000-0000-000000000004', true);
    IF EXISTS (SELECT 1 FROM export_batches) THEN RAISE EXCEPTION 'Suspended member read tenant data'; END IF;
    PERFORM set_config('app.user_id', '10000000-0000-0000-0000-000000000005', true);
    IF EXISTS (SELECT 1 FROM export_batches) THEN RAISE EXCEPTION 'Removed member read tenant data'; END IF;

    PERFORM set_config('search_path', 'pg_temp, public', true);
    CREATE TEMP TABLE organization_members(organization_id uuid, user_id uuid, status text);
    INSERT INTO organization_members VALUES (
        '20000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000005', 'ACTIVE'
    );
    IF app_tenant_access_allowed('20000000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'Temporary search-path object hijacked tenant membership';
    END IF;
    DROP TABLE organization_members;
    PERFORM set_config('search_path', 'pg_catalog, public', true);

    PERFORM set_config('app.user_id', '10000000-0000-0000-0000-000000000001', true);
    IF NOT EXISTS (SELECT 1 FROM countries WHERE iso2_code = 'VN')
       OR NOT has_table_privilege('themis_app', 'legal_documents', 'SELECT') THEN
        RAISE EXCEPTION 'Application role cannot read permitted global reference data';
    END IF;
    BEGIN
        UPDATE legal_documents SET title = title;
        RAISE EXCEPTION 'Application role updated global legal knowledge';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    audit_id_value := record_audit_event(
        '20000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'BATCH', 'BATCH_UPDATED', 'SUCCESS', 'API',
        'EXPORT_BATCH', '30000000-0000-0000-0000-000000000001'
    );
    PERFORM record_audit_log_change(audit_id_value, 'notes', 'null'::jsonb, '"reviewed"'::jsonb);
    PERFORM record_data_access(
        '20000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        'DOCUMENT', '40000000-0000-0000-0000-000000000001', 'VIEW'
    );
    IF NOT EXISTS (SELECT 1 FROM audit_logs WHERE id = audit_id_value)
       OR NOT EXISTS (SELECT 1 FROM audit_log_changes WHERE audit_log_id = audit_id_value)
       OR NOT EXISTS (SELECT 1 FROM data_access_logs WHERE resource_id = '40000000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'Approved audit/data-access functions did not persist tenant-visible history';
    END IF;
    BEGIN
        PERFORM record_audit_event(
            '20000000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000001',
            'SYSTEM', 'SPOOFED_SYSTEM', 'SUCCESS', 'SYSTEM_ADMIN'
        );
        RAISE EXCEPTION 'Application audit function accepted a privileged source';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM record_system_audit_event(NULL, 'SYSTEM', 'SPOOFED_SYSTEM', 'SUCCESS', 'SYSTEM');
        RAISE EXCEPTION 'Application role called the system audit path';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN UPDATE audit_logs SET action = 'REWRITTEN' WHERE id = audit_id_value;
        RAISE EXCEPTION 'Application role updated audit history';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN DELETE FROM audit_logs WHERE id = audit_id_value;
        RAISE EXCEPTION 'Application role deleted audit history';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN UPDATE audit_log_changes SET field_name = 'rewritten' WHERE audit_log_id = audit_id_value;
        RAISE EXCEPTION 'Application role updated audit changes';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN DELETE FROM data_access_logs WHERE resource_id = '40000000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'Application role deleted access history';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;

    BEGIN
        INSERT INTO export_batches(
            id, organization_id, batch_code, origin_country_id, destination_country_id,
            market_id, created_by
        ) SELECT
            '30000000-0000-0000-0000-000000000099',
            '20000000-0000-0000-0000-000000000001', 'RLS-ATOMIC-ROLLBACK',
            vn.id, cn.id, market_record.id, '10000000-0000-0000-0000-000000000001'
        FROM countries vn, countries cn, markets market_record
        WHERE vn.iso2_code = 'VN' AND cn.iso2_code = 'CN' AND market_record.code = 'CN_GACC';
        PERFORM record_audit_event(
            '20000000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000001',
            'BATCH', 'BATCH_CREATED_ATOMIC_TEST', 'SUCCESS', 'API',
            'EXPORT_BATCH', '30000000-0000-0000-0000-000000000099'
        );
        RAISE EXCEPTION 'rollback marker';
    EXCEPTION WHEN raise_exception THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM export_batches WHERE id = '30000000-0000-0000-0000-000000000099')
       OR EXISTS (SELECT 1 FROM audit_logs WHERE action = 'BATCH_CREATED_ATOMIC_TEST') THEN
        RAISE EXCEPTION 'Business mutation and audit were not transaction-atomic';
    END IF;

    BEGIN EXECUTE 'ALTER TABLE public.export_batches ADD COLUMN forbidden_column integer';
        RAISE EXCEPTION 'Application role altered a table';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN EXECUTE 'ALTER TABLE public.export_batches DISABLE TRIGGER ALL';
        RAISE EXCEPTION 'Application role disabled triggers';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN EXECUTE 'CREATE TABLE public.rls_escape(id integer)';
        RAISE EXCEPTION 'Application role created a public schema object';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;

    PERFORM set_config('row_security', 'off', true);
    BEGIN
        PERFORM count(*) FROM export_batches;
        RAISE EXCEPTION 'row_security=off bypassed RLS for the application role';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM set_config('row_security', 'on', true);
END $$;

RESET ROLE;

DO $$
DECLARE
    audit_id_value uuid;
BEGIN
    SELECT id INTO audit_id_value FROM audit_logs WHERE action = 'BATCH_UPDATED';
    BEGIN UPDATE audit_logs SET action = 'OWNER_REWRITE' WHERE id = audit_id_value;
        RAISE EXCEPTION 'Audit trigger allowed owner rewrite';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
    BEGIN DELETE FROM audit_log_changes WHERE audit_log_id = audit_id_value;
        RAISE EXCEPTION 'Audit change trigger allowed owner delete';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
    BEGIN DELETE FROM data_access_logs WHERE resource_id = '40000000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'Data access trigger allowed owner delete';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;

    BEGIN
        INSERT INTO system_job_runs(job_type, organization_id, idempotency_key)
        VALUES ('OCR', '20000000-0000-0000-0000-000000000001', 'RLS-JOB-A');
        RAISE EXCEPTION 'Duplicate tenant job idempotency key was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO system_job_runs(job_type, attempt_number, max_attempts)
        VALUES ('OCR', 2, 1);
        RAISE EXCEPTION 'Invalid job retry counters were accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    UPDATE system_job_runs
    SET status = 'RUNNING', started_at = clock_timestamp()
    WHERE id = '80000000-0000-0000-0000-000000000001';
    UPDATE system_job_runs
    SET status = 'COMPLETED', completed_at = clock_timestamp(),
        items_processed = 1, items_succeeded = 1
    WHERE id = '80000000-0000-0000-0000-000000000001';
    BEGIN
        UPDATE system_job_runs SET items_processed = 2
        WHERE id = '80000000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'Terminal system job history was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
END $$;

SET LOCAL ROLE themis_worker;
DO $$
BEGIN
    IF (SELECT count(*) FROM system_job_runs) <> 3 THEN
        RAISE EXCEPTION 'Explicit worker role cannot access its job queue';
    END IF;
END $$;
RESET ROLE;

ROLLBACK;

SELECT 'phase 10 RLS and security assertions passed' AS result;
