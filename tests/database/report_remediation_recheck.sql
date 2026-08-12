BEGIN;

DO $$
DECLARE
    vn_id uuid;
    cn_id uuid;
    market_id_value uuid;
    document_type_id uuid;
    manager_role_id uuid;
    staff_role_id uuid;
    manager_user uuid;
    assignee_one uuid;
    assignee_two uuid;
    other_user uuid;
    org_a uuid;
    org_b uuid;
    manager_member uuid;
    assignee_one_member uuid;
    assignee_two_member uuid;
    other_member uuid;
    batch_a uuid;
    batch_b uuid;
    batch_uncited uuid;
    batch_outside uuid;
    legal_source_id uuid;
    legal_document_id uuid;
    legal_version_id uuid;
    legal_file_id uuid;
    legal_section_id uuid;
    legal_requirement_id uuid;
    citation_id uuid;
    outside_document_id uuid;
    outside_version_id uuid;
    outside_section_id uuid;
    outside_citation_id uuid;
    rule_id uuid;
    rule_version_id uuid;
    source_document_id uuid;
    source_revision_id uuid;
    source_file_id uuid;
    source_job_id uuid;
    source_verification_id uuid;
    check_one uuid;
    check_noncompleted uuid;
    check_other_root uuid;
    check_wrong_parent_report uuid;
    execution_one uuid;
    finding_one uuid;
    report_one uuid;
    report_other_batch uuid;
    report_finding_one uuid;
    report_citation_one uuid;
    rejected_round integer;
    approved_round integer;
    task_id_value uuid;
    evidence_id_value uuid;
    review_id_value uuid;
    remediation_document_id uuid;
    remediation_revision_id uuid;
    remediation_file_id uuid;
    remediation_job_id uuid;
    remediation_verification_id uuid;
    draft_document_id uuid;
    draft_revision_id uuid;
    draft_verification_id uuid;
    recheck_id uuid;
    report_two uuid;
    uncited_check_id uuid;
    uncited_finding_id uuid;
    outside_check_id uuid;
    outside_finding_id uuid;
    old_check_created_at timestamptz;
    old_report_generated_at timestamptz;
    old_report_title text;
    snapshot_citation_label text;
    hash_source text := repeat('1', 64);
    hash_legal text := repeat('2', 64);
    hash_remediation text := repeat('3', 64);
BEGIN
    SELECT id INTO vn_id FROM countries WHERE iso2_code = 'VN';
    SELECT id INTO cn_id FROM countries WHERE iso2_code = 'CN';
    SELECT id INTO market_id_value FROM markets WHERE code = 'CN_GACC';
    SELECT id INTO document_type_id FROM document_types WHERE code = 'LAB_REPORT';
    SELECT id INTO manager_role_id FROM roles WHERE code = 'MANAGER';
    SELECT id INTO staff_role_id FROM roles WHERE code = 'STAFF';

    INSERT INTO users(email, full_name, status)
    VALUES ('phase08-manager@example.com', 'Phase 08 Manager', 'ACTIVE') RETURNING id INTO manager_user;
    INSERT INTO users(email, full_name, status)
    VALUES ('phase08-assignee1@example.com', 'Phase 08 Assignee One', 'ACTIVE') RETURNING id INTO assignee_one;
    INSERT INTO users(email, full_name, status)
    VALUES ('phase08-assignee2@example.com', 'Phase 08 Assignee Two', 'ACTIVE') RETURNING id INTO assignee_two;
    INSERT INTO users(email, full_name, status)
    VALUES ('phase08-other@example.com', 'Phase 08 Other', 'ACTIVE') RETURNING id INTO other_user;
    INSERT INTO organizations(name, created_by)
    VALUES ('Phase 08 Organization A', manager_user) RETURNING id INTO org_a;
    INSERT INTO organizations(name, created_by)
    VALUES ('Phase 08 Organization B', other_user) RETURNING id INTO org_b;
    INSERT INTO organization_members(organization_id, user_id, status, joined_at)
    VALUES (org_a, manager_user, 'ACTIVE', now()) RETURNING id INTO manager_member;
    INSERT INTO organization_members(organization_id, user_id, status, joined_at)
    VALUES (org_a, assignee_one, 'ACTIVE', now()) RETURNING id INTO assignee_one_member;
    INSERT INTO organization_members(organization_id, user_id, status, joined_at)
    VALUES (org_a, assignee_two, 'ACTIVE', now()) RETURNING id INTO assignee_two_member;
    INSERT INTO organization_members(organization_id, user_id, status, joined_at)
    VALUES (org_b, other_user, 'ACTIVE', now()) RETURNING id INTO other_member;
    INSERT INTO organization_member_roles(organization_id, organization_member_id, role_id)
    VALUES (org_a, manager_member, manager_role_id),
           (org_a, assignee_one_member, staff_role_id),
           (org_a, assignee_two_member, staff_role_id),
           (org_b, other_member, manager_role_id);

    IF NOT user_has_organization_permission(org_a, manager_user, 'REPORT_APPROVE')
       OR user_has_organization_permission(org_a, assignee_one, 'REPORT_APPROVE') THEN
        RAISE EXCEPTION 'Report approval RBAC policy is incorrect';
    END IF;

    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id, destination_country_id,
        market_id, created_by
    ) VALUES (org_a, 'PHASE08-A', vn_id, cn_id, market_id_value, manager_user)
    RETURNING id INTO batch_a;
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id, destination_country_id,
        market_id, created_by
    ) VALUES (org_a, 'PHASE08-B', vn_id, cn_id, market_id_value, manager_user)
    RETURNING id INTO batch_b;
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id, destination_country_id,
        market_id, created_by
    ) VALUES (org_a, 'PHASE08-UNCITED', vn_id, cn_id, market_id_value, manager_user)
    RETURNING id INTO batch_uncited;
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id, destination_country_id,
        market_id, created_by
    ) VALUES (org_a, 'PHASE08-OUTSIDE', vn_id, cn_id, market_id_value, manager_user)
    RETURNING id INTO batch_outside;

    INSERT INTO legal_sources(name, source_type, is_official, trust_level)
    VALUES ('TEST PHASE 08 SOURCE', 'OFFICIAL_PUBLICATION', true, 'PRIMARY')
    RETURNING id INTO legal_source_id;
    INSERT INTO legal_documents(source_id, title, document_type, jurisdiction_type, language_code)
    VALUES (legal_source_id, 'TEST Phase 08 legal document', 'REGULATION', 'NATIONAL', 'en')
    RETURNING id INTO legal_document_id;
    INSERT INTO legal_document_versions(
        legal_document_id, version_number, status, content_hash
    ) VALUES (legal_document_id, 1, 'UNDER_REVIEW', hash_legal)
    RETURNING id INTO legal_version_id;
    INSERT INTO legal_document_files(
        version_id, file_name, mime_type, storage_path, language_code,
        checksum_sha256, is_original
    ) VALUES (
        legal_version_id, 'phase08-law.pdf', 'application/pdf',
        'legal/phase08-law.pdf', 'en', hash_legal, true
    ) RETURNING id INTO legal_file_id;
    INSERT INTO legal_sections(version_id, section_type, content, order_index)
    VALUES (legal_version_id, 'ARTICLE', 'TEST Phase 08 legal section', 0)
    RETURNING id INTO legal_section_id;
    INSERT INTO legal_requirements(
        section_id, requirement_code, title, requirement_text,
        requirement_type, obligation_level, validation_type,
        severity_default, status
    ) VALUES (
        legal_section_id, 'TEST-P08-REQ', 'TEST Phase 08 requirement',
        'TEST transaction-only requirement', 'OTHER', 'MUST', 'BOOLEAN',
        'MEDIUM', 'ACTIVE'
    ) RETURNING id INTO legal_requirement_id;
    INSERT INTO legal_citations(
        version_id, section_id, requirement_id, citation_code,
        display_label, quote_excerpt, canonical_reference
    ) VALUES (
        legal_version_id, legal_section_id, legal_requirement_id,
        'TEST-P08-CIT', 'TEST Phase 08 citation',
        'TEST excerpt', 'TEST canonical reference'
    ) RETURNING id INTO citation_id;

    INSERT INTO legal_documents(source_id, title, document_type, jurisdiction_type, language_code)
    VALUES (legal_source_id, 'TEST outside legal document', 'REGULATION', 'NATIONAL', 'en')
    RETURNING id INTO outside_document_id;
    INSERT INTO legal_document_versions(
        legal_document_id, version_number, status, content_hash
    ) VALUES (outside_document_id, 1, 'UNDER_REVIEW', repeat('4', 64))
    RETURNING id INTO outside_version_id;
    INSERT INTO legal_sections(version_id, section_type, content, order_index)
    VALUES (outside_version_id, 'ARTICLE', 'TEST outside section', 0)
    RETURNING id INTO outside_section_id;
    INSERT INTO legal_citations(version_id, section_id, citation_code, display_label)
    VALUES (outside_version_id, outside_section_id, 'TEST-P08-OUT', 'TEST outside citation')
    RETURNING id INTO outside_citation_id;
    UPDATE legal_document_versions SET status = 'APPROVED'
    WHERE id IN (legal_version_id, outside_version_id);

    INSERT INTO compliance_rules(
        rule_code, legal_requirement_id, rule_type, name, status
    ) VALUES (
        'TEST-P08-RULE', legal_requirement_id, 'OTHER', 'TEST Phase 08 rule', 'ACTIVE'
    ) RETURNING id INTO rule_id;
    INSERT INTO compliance_rule_versions(
        rule_id, version_number, legal_document_version_id,
        condition_config, status
    ) VALUES (rule_id, 1, legal_version_id, '{"test":true}', 'ACTIVE')
    RETURNING id INTO rule_version_id;

    INSERT INTO documents(organization_id, document_type_id, title, created_by)
    VALUES (org_a, document_type_id, 'Phase 08 source evidence', manager_user)
    RETURNING id INTO source_document_id;
    INSERT INTO document_revisions(
        organization_id, document_id, revision_number, status,
        content_checksum, created_by
    ) VALUES (org_a, source_document_id, 1, 'DRAFT', hash_source, manager_user)
    RETURNING id INTO source_revision_id;
    INSERT INTO document_files(
        organization_id, document_revision_id, storage_provider, bucket_name,
        storage_path, original_file_name, mime_type, file_size_bytes,
        checksum_sha256, uploaded_by
    ) VALUES (
        org_a, source_revision_id, 'SUPABASE', 'private',
        'phase08/source.pdf', 'source.pdf', 'application/pdf', 100,
        hash_source, manager_user
    ) RETURNING id INTO source_file_id;
    INSERT INTO document_extraction_jobs(
        organization_id, document_revision_id, document_file_id,
        extraction_method, status, idempotency_key
    ) VALUES (
        org_a, source_revision_id, source_file_id,
        'MANUAL', 'COMPLETED', 'phase08-source-job'
    ) RETURNING id INTO source_job_id;
    INSERT INTO document_verifications(
        organization_id, document_revision_id, extraction_job_id, status
    ) VALUES (org_a, source_revision_id, source_job_id, 'PENDING')
    RETURNING id INTO source_verification_id;
    UPDATE document_verifications
    SET status = 'VERIFIED', verified_by = manager_user, verified_at = clock_timestamp()
    WHERE id = source_verification_id;
    UPDATE document_revisions
    SET status = 'VERIFIED', verified_at = clock_timestamp()
    WHERE id = source_revision_id;
    INSERT INTO batch_documents(organization_id, batch_id, document_id, attached_by)
    VALUES (org_a, batch_a, source_document_id, manager_user),
           (org_a, batch_b, source_document_id, manager_user);

    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by,
        check_number, status, idempotency_key, started_at
    ) VALUES (
        org_a, batch_a, market_id_value, manager_user,
        1, 'PROCESSING', 'phase08-check-1', now()
    ) RETURNING id INTO check_one;
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by,
        check_number, status, idempotency_key
    ) VALUES (
        org_a, batch_a, market_id_value, manager_user,
        2, 'QUEUED', 'phase08-noncompleted'
    ) RETURNING id INTO check_noncompleted;
    INSERT INTO compliance_check_documents(
        organization_id, check_id, document_id, document_revision_id,
        document_file_id, extraction_job_id, verification_id,
        document_checksum_snapshot, file_checksum_snapshot
    ) VALUES (
        org_a, check_one, source_document_id, source_revision_id,
        source_file_id, source_job_id, source_verification_id,
        hash_source, hash_source
    );
    INSERT INTO compliance_check_legal_versions(
        organization_id, check_id, legal_document_version_id
    ) VALUES (org_a, check_one, legal_version_id);
    INSERT INTO rule_executions(
        organization_id, check_id, rule_version_id, status, outcome,
        started_at, completed_at
    ) VALUES (
        org_a, check_one, rule_version_id, 'COMPLETED', 'FAIL', now(), now()
    ) RETURNING id INTO execution_one;
    INSERT INTO findings(
        organization_id, check_id, rule_execution_id, source_type,
        finding_type, title, description, severity, validation_status,
        actual_value, expected_value, unit_text, remediation_hint
    ) VALUES (
        org_a, check_one, execution_one, 'RULE_ENGINE', 'TEST_DEFICIENCY',
        'TEST finding title', 'TEST finding description', 'MEDIUM', 'VALIDATED',
        'actual', 'expected', 'unit', 'TEST remediation hint'
    ) RETURNING id INTO finding_one;
    INSERT INTO finding_citations(finding_id, citation_id, is_primary)
    VALUES (finding_one, citation_id, true);
    UPDATE compliance_checks
    SET status = 'COMPLETED', overall_result = 'ACTION_REQUIRED', completed_at = clock_timestamp()
    WHERE id = check_one;
    SELECT created_at INTO old_check_created_at FROM compliance_checks WHERE id = check_one;

    BEGIN
        PERFORM generate_compliance_report(
            org_a, check_noncompleted, manager_user,
            'TEST-P08-NONCOMPLETED', 'TEST noncompleted', NULL
        );
        RAISE EXCEPTION 'Non-completed check generated a report';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO compliance_reports(
            organization_id, check_id, batch_id, version_number, report_code,
            overall_result, title, generated_by
        ) VALUES (
            org_a, check_one, batch_a, 1, 'TEST-P08-WRONG-RESULT',
            'COMPLIANT', 'TEST wrong result', manager_user
        );
        RAISE EXCEPTION 'Report result different from completed check was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    report_one := generate_compliance_report(
        org_a, check_one, manager_user, 'TEST-P08-R1',
        'TEST compliance report v1', 'TEST executive summary'
    );
    SELECT id INTO report_finding_one FROM report_findings
    WHERE report_id = report_one AND finding_id = finding_one;
    SELECT id, display_label_snapshot INTO report_citation_one, snapshot_citation_label
    FROM report_finding_citations
    WHERE report_finding_id = report_finding_one AND source_citation_id = citation_id;
    IF report_finding_one IS NULL OR report_citation_one IS NULL
       OR (SELECT overall_result FROM compliance_reports WHERE id = report_one) <> 'ACTION_REQUIRED'
       OR (SELECT source_file_checksum_snapshot FROM report_finding_citations WHERE id = report_citation_one) <> hash_legal THEN
        RAISE EXCEPTION 'Atomic report/finding/citation snapshot generation failed';
    END IF;
    SELECT generated_at, title INTO old_report_generated_at, old_report_title
    FROM compliance_reports WHERE id = report_one;

    BEGIN
        PERFORM generate_compliance_report(
            org_a, check_one, manager_user, 'TEST-P08-R1-DUP', 'TEST duplicate report', NULL
        );
        RAISE EXCEPTION 'A second report for the same check was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    UPDATE compliance_checks
    SET status = 'PROCESSING', started_at = clock_timestamp()
    WHERE id = check_noncompleted;
    INSERT INTO compliance_check_documents(
        organization_id, check_id, document_id, document_revision_id,
        document_file_id, extraction_job_id, verification_id,
        document_checksum_snapshot, file_checksum_snapshot
    ) VALUES (
        org_a, check_noncompleted, source_document_id, source_revision_id,
        source_file_id, source_job_id, source_verification_id, hash_source, hash_source
    );
    INSERT INTO compliance_check_legal_versions(organization_id, check_id, legal_document_version_id)
    VALUES (org_a, check_noncompleted, legal_version_id);
    INSERT INTO rule_executions(organization_id, check_id, rule_version_id, status, outcome)
    VALUES (org_a, check_noncompleted, rule_version_id, 'COMPLETED', 'PASS');
    UPDATE compliance_checks
    SET status = 'COMPLETED', overall_result = 'COMPLIANT', completed_at = clock_timestamp()
    WHERE id = check_noncompleted;
    BEGIN
        PERFORM generate_compliance_report(
            org_a, check_noncompleted, manager_user,
            'TEST-P08-DUP-BATCH-VERSION', 'TEST duplicate batch version', NULL
        );
        RAISE EXCEPTION 'Duplicate report version in one organization/batch was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO report_findings(
            organization_id, check_id, report_id, finding_id, display_order,
            source_type_snapshot, finding_type_snapshot, title_snapshot,
            description_snapshot, severity_snapshot, validation_status_snapshot
        ) VALUES (
            org_a, check_noncompleted, report_one, finding_one, 99,
            'RULE_ENGINE', 'TEST', 'TEST', 'TEST', 'LOW', 'REJECTED'
        );
        RAISE EXCEPTION 'Finding outside the report check was accepted';
    EXCEPTION WHEN foreign_key_violation OR check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO report_finding_citations(
            organization_id, report_finding_id, source_citation_id,
            citation_code_snapshot, display_label_snapshot,
            legal_document_id, legal_document_version_id, legal_section_id,
            legal_requirement_id, legal_version_content_hash_snapshot
        ) VALUES (
            org_a, report_finding_one, citation_id,
            'TEST-P08-CIT', 'TEST Phase 08 citation',
            legal_document_id, legal_version_id, outside_section_id,
            legal_requirement_id, hash_legal
        );
        RAISE EXCEPTION 'Citation/version/section provenance mismatch was accepted';
    EXCEPTION WHEN foreign_key_violation OR check_violation THEN NULL;
    END;

    -- Build a completed root check on another batch to exercise batch/version and parent-report safety.
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by,
        check_number, status, idempotency_key, started_at
    ) VALUES (
        org_a, batch_b, market_id_value, manager_user,
        1, 'PROCESSING', 'phase08-other-root', now()
    ) RETURNING id INTO check_other_root;
    INSERT INTO compliance_check_documents(
        organization_id, check_id, document_id, document_revision_id,
        document_file_id, extraction_job_id, verification_id,
        document_checksum_snapshot, file_checksum_snapshot
    ) VALUES (
        org_a, check_other_root, source_document_id, source_revision_id,
        source_file_id, source_job_id, source_verification_id, hash_source, hash_source
    );
    INSERT INTO compliance_check_legal_versions(organization_id, check_id, legal_document_version_id)
    VALUES (org_a, check_other_root, legal_version_id);
    INSERT INTO rule_executions(organization_id, check_id, rule_version_id, status, outcome)
    VALUES (org_a, check_other_root, rule_version_id, 'COMPLETED', 'PASS');
    UPDATE compliance_checks
    SET status = 'COMPLETED', overall_result = 'COMPLIANT', completed_at = clock_timestamp()
    WHERE id = check_other_root;
    report_other_batch := generate_compliance_report(
        org_a, check_other_root, manager_user,
        'TEST-P08-OTHER-R1', 'TEST other batch report', NULL
    );
    BEGIN
        INSERT INTO compliance_reports(
            organization_id, check_id, batch_id, version_number, report_code,
            overall_result, title, generated_by
        ) VALUES (
            org_a, check_other_root, batch_b, 1, 'TEST-P08-OTHER-DUP-VERSION',
            'COMPLIANT', 'TEST duplicate version', manager_user
        );
        RAISE EXCEPTION 'Duplicate batch report version was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    -- Explicitly exercise defensive generation failures for corrupted legacy invariants.
    PERFORM set_config('session_replication_role', 'replica', true);
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number,
        status, overall_result, completed_at
    ) VALUES (
        org_a, batch_uncited, market_id_value, manager_user, 1,
        'COMPLETED', 'MANUAL_REVIEW_REQUIRED', now()
    ) RETURNING id INTO uncited_check_id;
    INSERT INTO findings(
        organization_id, check_id, source_type, finding_type,
        title, description, severity, validation_status
    ) VALUES (
        org_a, uncited_check_id, 'MANUAL', 'TEST_UNCITED',
        'TEST uncited', 'TEST corrupted legacy invariant', 'HIGH', 'VALIDATED'
    ) RETURNING id INTO uncited_finding_id;
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number,
        status, overall_result, completed_at
    ) VALUES (
        org_a, batch_outside, market_id_value, manager_user, 1,
        'COMPLETED', 'MANUAL_REVIEW_REQUIRED', now()
    ) RETURNING id INTO outside_check_id;
    INSERT INTO compliance_check_legal_versions(organization_id, check_id, legal_document_version_id)
    VALUES (org_a, outside_check_id, legal_version_id);
    INSERT INTO findings(
        organization_id, check_id, source_type, finding_type,
        title, description, severity, validation_status
    ) VALUES (
        org_a, outside_check_id, 'MANUAL', 'TEST_OUTSIDE_CITATION',
        'TEST outside citation', 'TEST corrupted outside citation invariant',
        'HIGH', 'VALIDATED'
    ) RETURNING id INTO outside_finding_id;
    INSERT INTO finding_citations(finding_id, citation_id, is_primary)
    VALUES (outside_finding_id, outside_citation_id, true);
    PERFORM set_config('session_replication_role', 'origin', true);
    BEGIN
        PERFORM generate_compliance_report(
            org_a, uncited_check_id, manager_user,
            'TEST-P08-UNCITED-R', 'TEST uncited report', NULL
        );
        RAISE EXCEPTION 'Report generation accepted a validated finding without citation';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        PERFORM generate_compliance_report(
            org_a, outside_check_id, manager_user,
            'TEST-P08-OUTSIDE-R', 'TEST outside citation report', NULL
        );
        RAISE EXCEPTION 'Report generation accepted a citation outside the check legal snapshot';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    rejected_round := submit_compliance_report(org_a, report_one, manager_user);
    IF rejected_round <> 1 OR (SELECT status FROM compliance_reports WHERE id = report_one) <> 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'Draft submission did not create approval round 1';
    END IF;
    INSERT INTO report_approvals(
        organization_id, report_id, submission_round, reviewer_id, decision, comment
    ) VALUES (org_a, report_one, 1, manager_user, 'REJECTED', 'TEST revise report');
    BEGIN
        INSERT INTO report_approvals(
            organization_id, report_id, submission_round, reviewer_id, decision
        ) VALUES (org_a, report_one, 1, manager_user, 'APPROVED');
        RAISE EXCEPTION 'Duplicate reviewer decision in one round was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    UPDATE compliance_reports
    SET status = 'REJECTED', updated_at = clock_timestamp()
    WHERE id = report_one;
    PERFORM return_rejected_report_to_draft(org_a, report_one, manager_user);
    approved_round := submit_compliance_report(org_a, report_one, manager_user);
    IF approved_round <> 2 THEN
        RAISE EXCEPTION 'Rejected report resubmission did not increment the round';
    END IF;
    PERFORM decide_compliance_report(
        org_a, report_one, manager_user, 'APPROVED', 'TEST approved round 2'
    );
    IF (SELECT status FROM compliance_reports WHERE id = report_one) <> 'APPROVED' THEN
        RAISE EXCEPTION 'Report approval did not finalize the report';
    END IF;

    BEGIN
        UPDATE compliance_reports SET title = 'REWRITTEN' WHERE id = report_one;
        RAISE EXCEPTION 'Approved report was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        UPDATE report_findings SET title_snapshot = 'REWRITTEN' WHERE id = report_finding_one;
        RAISE EXCEPTION 'Approved report finding snapshot was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        DELETE FROM report_finding_citations WHERE id = report_citation_one;
        RAISE EXCEPTION 'Approved report citation snapshot was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        UPDATE report_approvals SET comment = 'REWRITTEN'
        WHERE report_id = report_one AND submission_round = 2;
        RAISE EXCEPTION 'Approved report approval history was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        UPDATE legal_citations SET display_label = 'REWRITTEN' WHERE id = citation_id;
        RAISE EXCEPTION 'Approved legal source citation was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    IF (SELECT display_label_snapshot FROM report_finding_citations WHERE id = report_citation_one)
       <> snapshot_citation_label THEN
        RAISE EXCEPTION 'Approved citation snapshot changed with its source';
    END IF;

    task_id_value := create_remediation_task(
        org_a, report_one, finding_one, 'TEST remediation task',
        'TEST correct the cited deficiency', 'HIGH', current_date + 7, manager_user
    );
    BEGIN
        INSERT INTO remediation_tasks(
            organization_id, batch_id, report_id, finding_id, title,
            priority, created_by
        ) VALUES (
            org_b, batch_a, report_one, finding_one, 'TEST cross tenant',
            'HIGH', other_user
        );
        RAISE EXCEPTION 'Cross-tenant remediation task was accepted';
    EXCEPTION WHEN foreign_key_violation OR check_violation OR insufficient_privilege THEN NULL;
    END;
    BEGIN
        INSERT INTO remediation_tasks(
            organization_id, batch_id, report_id, finding_id, title,
            priority, created_by
        ) VALUES (
            org_a, batch_a, report_one, gen_random_uuid(), 'TEST wrong finding',
            'HIGH', manager_user
        );
        RAISE EXCEPTION 'Task finding outside its report was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    PERFORM assign_remediation_task(org_a, task_id_value, assignee_one, manager_user);
    PERFORM assign_remediation_task(org_a, task_id_value, assignee_two, manager_user);
    IF (SELECT count(*) FROM remediation_task_assignees WHERE task_id = task_id_value) <> 2 THEN
        RAISE EXCEPTION 'Multiple remediation assignees were not preserved';
    END IF;
    BEGIN
        PERFORM assign_remediation_task(org_a, task_id_value, assignee_one, manager_user);
        RAISE EXCEPTION 'Duplicate remediation assignee was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    PERFORM start_remediation_task(org_a, task_id_value, assignee_one);
    BEGIN
        PERFORM create_recheck_for_report(org_a, report_one, manager_user, 'phase08-blocked-recheck');
        RAISE EXCEPTION 'Unresolved remediation allowed a re-check';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        PERFORM create_recheck_for_report(org_a, report_one, manager_user, NULL);
        RAISE EXCEPTION 'Re-check without an idempotency key was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    INSERT INTO documents(organization_id, document_type_id, title, created_by)
    VALUES (org_a, document_type_id, 'TEST draft remediation evidence', assignee_one)
    RETURNING id INTO draft_document_id;
    INSERT INTO document_revisions(
        organization_id, document_id, revision_number, status, created_by
    ) VALUES (org_a, draft_document_id, 1, 'DRAFT', assignee_one)
    RETURNING id INTO draft_revision_id;
    INSERT INTO document_verifications(organization_id, document_revision_id, status)
    VALUES (org_a, draft_revision_id, 'PENDING')
    RETURNING id INTO draft_verification_id;
    BEGIN
        PERFORM submit_remediation_evidence(
            org_a, task_id_value, draft_document_id, draft_revision_id,
            draft_verification_id, assignee_one, 'TEST unverified evidence'
        );
        RAISE EXCEPTION 'Unverified remediation evidence was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    INSERT INTO documents(organization_id, document_type_id, title, created_by)
    VALUES (org_a, document_type_id, 'TEST verified remediation evidence', assignee_one)
    RETURNING id INTO remediation_document_id;
    INSERT INTO document_revisions(
        organization_id, document_id, revision_number, status,
        content_checksum, created_by
    ) VALUES (
        org_a, remediation_document_id, 1, 'DRAFT', hash_remediation, assignee_one
    ) RETURNING id INTO remediation_revision_id;
    INSERT INTO document_files(
        organization_id, document_revision_id, storage_provider, bucket_name,
        storage_path, original_file_name, mime_type, file_size_bytes,
        checksum_sha256, uploaded_by
    ) VALUES (
        org_a, remediation_revision_id, 'SUPABASE', 'private',
        'phase08/remediation.pdf', 'remediation.pdf', 'application/pdf', 100,
        hash_remediation, assignee_one
    ) RETURNING id INTO remediation_file_id;
    INSERT INTO document_extraction_jobs(
        organization_id, document_revision_id, document_file_id,
        extraction_method, status, idempotency_key
    ) VALUES (
        org_a, remediation_revision_id, remediation_file_id,
        'MANUAL', 'COMPLETED', 'phase08-remediation-job'
    ) RETURNING id INTO remediation_job_id;
    INSERT INTO document_verifications(
        organization_id, document_revision_id, extraction_job_id, status
    ) VALUES (org_a, remediation_revision_id, remediation_job_id, 'PENDING')
    RETURNING id INTO remediation_verification_id;
    UPDATE document_verifications
    SET status = 'VERIFIED', verified_by = manager_user, verified_at = clock_timestamp()
    WHERE id = remediation_verification_id;
    UPDATE document_revisions
    SET status = 'VERIFIED', verified_at = clock_timestamp()
    WHERE id = remediation_revision_id;
    INSERT INTO batch_documents(organization_id, batch_id, document_id, attached_by)
    VALUES (org_a, batch_a, remediation_document_id, manager_user);

    BEGIN
        INSERT INTO remediation_evidence(
            organization_id, task_id, document_id, document_revision_id,
            verification_id, submitted_by
        ) VALUES (
            org_b, task_id_value, remediation_document_id,
            remediation_revision_id, remediation_verification_id, other_user
        );
        RAISE EXCEPTION 'Cross-tenant remediation evidence was accepted';
    EXCEPTION WHEN foreign_key_violation OR check_violation THEN NULL;
    END;
    evidence_id_value := submit_remediation_evidence(
        org_a, task_id_value, remediation_document_id, remediation_revision_id,
        remediation_verification_id, assignee_one, 'TEST exact verified evidence'
    );
    PERFORM decide_remediation_evidence(
        org_a, evidence_id_value, manager_user, 'ACCEPTED'
    );
    review_id_value := review_remediation_task(
        org_a, task_id_value, manager_user, 'APPROVED', 'TEST remediation accepted'
    );
    IF (SELECT status FROM remediation_tasks WHERE id = task_id_value) <> 'APPROVED'
       OR (SELECT status FROM remediation_evidence WHERE id = evidence_id_value) <> 'ACCEPTED' THEN
        RAISE EXCEPTION 'Accepted evidence and task approval workflow failed';
    END IF;
    BEGIN
        UPDATE remediation_reviews SET comment = 'REWRITTEN' WHERE id = review_id_value;
        RAISE EXCEPTION 'Remediation review history was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        UPDATE remediation_task_events SET event_type = 'REWRITTEN' WHERE task_id = task_id_value;
        RAISE EXCEPTION 'Remediation event history was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        UPDATE remediation_evidence SET description = 'REWRITTEN' WHERE id = evidence_id_value;
        RAISE EXCEPTION 'Reviewed remediation evidence provenance was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    -- Existing FK also rejects a parent check from another batch.
    BEGIN
        INSERT INTO compliance_checks(
            organization_id, batch_id, market_id, created_by,
            parent_check_id, check_number
        ) VALUES (
            org_a, batch_b, market_id_value, manager_user, check_one, 2
        );
        RAISE EXCEPTION 'Cross-batch re-check parent was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    recheck_id := create_recheck_for_report(
        org_a, report_one, manager_user, 'phase08-recheck-approved'
    );
    IF recheck_id = check_one
       OR NOT EXISTS (
           SELECT 1 FROM compliance_checks
           WHERE id = recheck_id AND parent_check_id = check_one
             AND batch_id = batch_a AND status = 'QUEUED'
       )
       OR (SELECT created_at FROM compliance_checks WHERE id = check_one) <> old_check_created_at THEN
        RAISE EXCEPTION 'Re-check did not create an independent same-batch child check';
    END IF;

    UPDATE compliance_checks
    SET status = 'PROCESSING', started_at = clock_timestamp()
    WHERE id = recheck_id;
    INSERT INTO compliance_check_documents(
        organization_id, check_id, document_id, document_revision_id,
        document_file_id, extraction_job_id, verification_id,
        document_checksum_snapshot, file_checksum_snapshot
    ) VALUES (
        org_a, recheck_id, remediation_document_id, remediation_revision_id,
        remediation_file_id, remediation_job_id, remediation_verification_id,
        hash_remediation, hash_remediation
    );
    INSERT INTO compliance_check_legal_versions(organization_id, check_id, legal_document_version_id)
    VALUES (org_a, recheck_id, legal_version_id);
    INSERT INTO rule_executions(organization_id, check_id, rule_version_id, status, outcome)
    VALUES (org_a, recheck_id, rule_version_id, 'COMPLETED', 'PASS');
    UPDATE compliance_checks
    SET status = 'COMPLETED', overall_result = 'COMPLIANT', completed_at = clock_timestamp()
    WHERE id = recheck_id;
    report_two := generate_compliance_report(
        org_a, recheck_id, manager_user, 'TEST-P08-R2',
        'TEST compliance report v2', NULL
    );
    IF NOT EXISTS (
        SELECT 1 FROM compliance_reports
        WHERE id = report_two AND parent_report_id = report_one
          AND version_number = 2 AND check_id = recheck_id
    ) THEN
        RAISE EXCEPTION 'Completed re-check did not generate report v2 lineage';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM compliance_reports
        WHERE id = report_one AND status = 'APPROVED'
          AND generated_at = old_report_generated_at AND title = old_report_title
    ) OR NOT EXISTS (
        SELECT 1 FROM compliance_checks
        WHERE id = check_one AND status = 'COMPLETED' AND overall_result = 'ACTION_REQUIRED'
    ) THEN
        RAISE EXCEPTION 'Old check/report history changed during remediation or re-check';
    END IF;

    -- A completed re-check report cannot point to a report from another batch.
    BEGIN
        INSERT INTO compliance_reports(
            organization_id, check_id, batch_id, parent_report_id,
            version_number, report_code, overall_result, title, generated_by
        ) VALUES (
            org_a, recheck_id, batch_a, report_other_batch,
            2, 'TEST-P08-WRONG-PARENT', 'COMPLIANT', 'TEST wrong parent', manager_user
        );
        RAISE EXCEPTION 'Parent report from another batch was accepted';
    EXCEPTION WHEN foreign_key_violation OR check_violation THEN NULL;
    END;
END $$;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

SELECT 'phase 08 report remediation re-check assertions passed' AS result;
