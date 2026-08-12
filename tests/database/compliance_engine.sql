BEGIN;

DO $$
DECLARE
    vn_id uuid;
    cn_id uuid;
    market_id_value uuid;
    product_id_value uuid;
    form_id_value uuid;
    ppm_id uuid;
    canonical_unit_id uuid;
    mass_unit_id uuid;
    source_id_value uuid;
    authority_id_value uuid;
    legal_document_id_value uuid;
    other_legal_document_id uuid;
    legal_version_id_value uuid;
    other_legal_version_id uuid;
    new_legal_version_id uuid;
    section_id_value uuid;
    other_section_id uuid;
    requirement_id_value uuid;
    other_requirement_id uuid;
    citation_id_value uuid;
    rule_id_value uuid;
    other_rule_id uuid;
    rule_version_id_value uuid;
    inactive_rule_version_id uuid;
    user_a uuid;
    user_b uuid;
    org_a uuid;
    org_b uuid;
    batch_a uuid;
    batch_a_other uuid;
    batch_b uuid;
    document_id_value uuid;
    other_document_id uuid;
    document_type_value uuid;
    revision_id_value uuid;
    other_revision_id uuid;
    file_id_value uuid;
    other_file_id uuid;
    job_id_value uuid;
    other_job_id uuid;
    verification_id_value uuid;
    other_verification_id uuid;
    check_pass uuid;
    check_noncompliant uuid;
    check_action uuid;
    check_review uuid;
    recheck_id_value uuid;
    pass_execution_id uuid;
    fail_execution_id uuid;
    action_execution_id uuid;
    review_execution_id uuid;
    high_finding_id uuid;
    action_finding_id uuid;
    review_finding_id uuid;
    manual_finding_id uuid;
    entity_id_value uuid;
    hash_value text := repeat('6', 64);
    selected_scope_id uuid;
    specific_scope_id uuid;
    tie_count integer;
BEGIN
    SELECT id INTO vn_id FROM countries WHERE iso2_code = 'VN';
    SELECT id INTO cn_id FROM countries WHERE iso2_code = 'CN';
    SELECT id INTO market_id_value FROM markets WHERE code = 'CN_GACC';
    SELECT id INTO product_id_value FROM products WHERE code = 'DURIAN';
    SELECT id INTO form_id_value FROM product_forms
    WHERE product_id = product_id_value AND code = 'FRESH';
    SELECT id INTO ppm_id FROM measurement_units WHERE code = 'PPM';
    SELECT id INTO canonical_unit_id FROM measurement_units WHERE code = 'MG_PER_KG';
    SELECT id INTO mass_unit_id FROM measurement_units WHERE code = 'KG';

    INSERT INTO legal_sources(name, source_type, is_official, trust_level)
    VALUES ('TEST COMPLIANCE SOURCE', 'OFFICIAL_PUBLICATION', true, 'PRIMARY')
    RETURNING id INTO source_id_value;
    INSERT INTO legal_authorities(country_id, code, name)
    VALUES (vn_id, 'TEST_COMPLIANCE_AUTH', 'TEST Compliance Authority')
    RETURNING id INTO authority_id_value;
    INSERT INTO legal_documents(
        source_id, title, document_type, jurisdiction_type, language_code
    ) VALUES (
        source_id_value, 'TEST Compliance Legal Document',
        'REGULATION', 'NATIONAL', 'en'
    ) RETURNING id INTO legal_document_id_value;
    INSERT INTO legal_documents(
        source_id, title, document_type, jurisdiction_type, language_code
    ) VALUES (
        source_id_value, 'TEST Other Legal Document',
        'REGULATION', 'NATIONAL', 'en'
    ) RETURNING id INTO other_legal_document_id;
    INSERT INTO legal_document_versions(
        legal_document_id, version_number, effective_from, status, content_hash
    ) VALUES (
        legal_document_id_value, 1, DATE '2026-01-01', 'UNDER_REVIEW', hash_value
    ) RETURNING id INTO legal_version_id_value;
    INSERT INTO legal_document_versions(
        legal_document_id, version_number, effective_from, status, content_hash
    ) VALUES (
        other_legal_document_id, 1, DATE '2026-01-01', 'UNDER_REVIEW', repeat('7', 64)
    ) RETURNING id INTO other_legal_version_id;
    INSERT INTO legal_sections(version_id, section_type, content, order_index)
    VALUES (legal_version_id_value, 'ARTICLE', 'TEST compliance section', 1)
    RETURNING id INTO section_id_value;
    INSERT INTO legal_sections(version_id, section_type, content, order_index)
    VALUES (other_legal_version_id, 'ARTICLE', 'TEST other section', 1)
    RETURNING id INTO other_section_id;
    INSERT INTO legal_requirements(
        section_id, requirement_code, title, requirement_text,
        requirement_type, obligation_level, validation_type,
        severity_default, effective_from, status
    ) VALUES (
        section_id_value, 'TEST-COMPLIANCE-REQ', 'TEST compliance requirement',
        'TEST compliance requirement text', 'PESTICIDE_RESIDUE', 'MUST',
        'NUMERIC_LIMIT', 'HIGH', DATE '2026-01-01', 'ACTIVE'
    ) RETURNING id INTO requirement_id_value;
    INSERT INTO legal_requirements(
        section_id, requirement_code, title, requirement_text,
        requirement_type, obligation_level, validation_type,
        severity_default, status
    ) VALUES (
        other_section_id, 'TEST-OTHER-COMPLIANCE-REQ', 'Other requirement',
        'Other requirement text', 'OTHER', 'MUST', 'OTHER', 'LOW', 'ACTIVE'
    ) RETURNING id INTO other_requirement_id;

    INSERT INTO requirement_scopes(requirement_id, priority)
    VALUES (requirement_id_value, 0);
    INSERT INTO requirement_scopes(
        requirement_id, product_id, product_form_id, market_id, priority
    ) VALUES (
        requirement_id_value, product_id_value, form_id_value, market_id_value, 0
    ) RETURNING id INTO specific_scope_id;
    INSERT INTO requirement_scopes(
        requirement_id, product_id, product_form_id, market_id, priority
    ) VALUES (
        requirement_id_value, product_id_value, form_id_value, market_id_value, 0
    );

    INSERT INTO legal_citations(
        version_id, section_id, requirement_id, citation_code, display_label
    ) VALUES (
        legal_version_id_value, section_id_value, requirement_id_value,
        'TEST-COMPLIANCE-CITATION', 'TEST compliance citation'
    ) RETURNING id INTO citation_id_value;

    UPDATE legal_document_versions SET status = 'APPROVED'
    WHERE id IN (legal_version_id_value, other_legal_version_id);

    INSERT INTO compliance_rules(
        rule_code, legal_requirement_id, rule_type, name, status
    ) VALUES (
        'TEST-COMPLIANCE-RULE', requirement_id_value,
        'NUMERIC_LIMIT', 'TEST numeric rule', 'ACTIVE'
    ) RETURNING id INTO rule_id_value;

    BEGIN
        INSERT INTO compliance_rules(rule_code, legal_requirement_id, rule_type, name)
        VALUES ('TEST-NO-REQUIREMENT', NULL, 'OTHER', 'No requirement');
        RAISE EXCEPTION 'Compliance rule without requirement was accepted';
    EXCEPTION WHEN not_null_violation THEN
        NULL;
    END;

    INSERT INTO compliance_rules(
        rule_code, legal_requirement_id, rule_type, name
    ) VALUES (
        'TEST-OTHER-RULE', other_requirement_id, 'OTHER', 'Other rule'
    ) RETURNING id INTO other_rule_id;

    INSERT INTO compliance_rule_versions(
        rule_id, version_number, legal_document_version_id,
        condition_config, effective_from, status
    ) VALUES (
        rule_id_value, 1, legal_version_id_value,
        '{"operator":"LTE","legal_limit_reference":"required"}'::jsonb,
        DATE '2026-01-01', 'ACTIVE'
    ) RETURNING id INTO rule_version_id_value;

    BEGIN
        INSERT INTO compliance_rule_versions(
            rule_id, version_number, legal_document_version_id, condition_config
        ) VALUES (rule_id_value, 1, legal_version_id_value, '{}'::jsonb);
        RAISE EXCEPTION 'Duplicate compliance rule version was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO compliance_rule_versions(
            rule_id, version_number, legal_document_version_id, condition_config
        ) VALUES (rule_id_value, 2, other_legal_version_id, '{}'::jsonb);
        RAISE EXCEPTION 'Rule/legal requirement provenance mismatch was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO compliance_rule_versions(
        rule_id, version_number, legal_document_version_id,
        condition_config, effective_from, effective_to, status
    ) VALUES (
        rule_id_value, 3, legal_version_id_value, '{"disabled":"test"}'::jsonb,
        DATE '2020-01-01', DATE '2020-12-31', 'INACTIVE'
    ) RETURNING id INTO inactive_rule_version_id;

    BEGIN
        UPDATE compliance_rule_versions
        SET condition_config = '{"operator":"GT"}'::jsonb
        WHERE id = rule_version_id_value;
        RAISE EXCEPTION 'Active compliance rule version was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    INSERT INTO users(email, full_name, status)
    VALUES ('compliance-a@example.com', 'Compliance A', 'ACTIVE') RETURNING id INTO user_a;
    INSERT INTO users(email, full_name, status)
    VALUES ('compliance-b@example.com', 'Compliance B', 'ACTIVE') RETURNING id INTO user_b;
    INSERT INTO organizations(name, created_by)
    VALUES ('Compliance Org A', user_a) RETURNING id INTO org_a;
    INSERT INTO organizations(name, created_by)
    VALUES ('Compliance Org B', user_b) RETURNING id INTO org_b;
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id,
        destination_country_id, market_id, created_by
    ) VALUES (org_a, 'CHECK-BATCH-A', vn_id, cn_id, market_id_value, user_a)
    RETURNING id INTO batch_a;
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id,
        destination_country_id, market_id, created_by
    ) VALUES (org_a, 'CHECK-BATCH-A2', vn_id, cn_id, market_id_value, user_a)
    RETURNING id INTO batch_a_other;
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id,
        destination_country_id, market_id, created_by
    ) VALUES (org_b, 'CHECK-BATCH-B', vn_id, cn_id, market_id_value, user_b)
    RETURNING id INTO batch_b;

    SELECT id INTO document_type_value FROM document_types WHERE code = 'LAB_REPORT';
    INSERT INTO documents(organization_id, document_type_id, title, created_by)
    VALUES (org_a, document_type_value, 'Compliance evidence', user_a)
    RETURNING id INTO document_id_value;
    INSERT INTO documents(organization_id, document_type_id, title, created_by)
    VALUES (org_a, document_type_value, 'Other evidence', user_a)
    RETURNING id INTO other_document_id;
    INSERT INTO document_revisions(
        organization_id, document_id, revision_number,
        status, content_checksum, created_by
    ) VALUES (org_a, document_id_value, 1, 'DRAFT', hash_value, user_a)
    RETURNING id INTO revision_id_value;
    INSERT INTO document_revisions(
        organization_id, document_id, revision_number,
        status, content_checksum, created_by
    ) VALUES (org_a, other_document_id, 1, 'DRAFT', hash_value, user_a)
    RETURNING id INTO other_revision_id;
    INSERT INTO document_files(
        organization_id, document_revision_id, storage_provider, bucket_name,
        storage_path, original_file_name, mime_type, file_size_bytes,
        checksum_sha256, uploaded_by
    ) VALUES (
        org_a, revision_id_value, 'SUPABASE', 'private', 'checks/evidence.pdf',
        'evidence.pdf', 'application/pdf', 100, hash_value, user_a
    ) RETURNING id INTO file_id_value;
    INSERT INTO document_files(
        organization_id, document_revision_id, storage_provider, bucket_name,
        storage_path, original_file_name, mime_type, file_size_bytes,
        checksum_sha256, uploaded_by
    ) VALUES (
        org_a, other_revision_id, 'SUPABASE', 'private', 'checks/other.pdf',
        'other.pdf', 'application/pdf', 100, hash_value, user_a
    ) RETURNING id INTO other_file_id;
    INSERT INTO document_extraction_jobs(
        organization_id, document_revision_id, document_file_id,
        extraction_method, status, idempotency_key
    ) VALUES (
        org_a, revision_id_value, file_id_value,
        'MANUAL', 'COMPLETED', 'check-extraction-main'
    ) RETURNING id INTO job_id_value;
    INSERT INTO document_extraction_jobs(
        organization_id, document_revision_id, document_file_id,
        extraction_method, status, idempotency_key
    ) VALUES (
        org_a, other_revision_id, other_file_id,
        'MANUAL', 'COMPLETED', 'check-extraction-other'
    ) RETURNING id INTO other_job_id;
    INSERT INTO document_verifications(
        organization_id, document_revision_id, extraction_job_id, status
    ) VALUES (org_a, revision_id_value, job_id_value, 'PENDING')
    RETURNING id INTO verification_id_value;
    INSERT INTO document_verifications(
        organization_id, document_revision_id, extraction_job_id, status
    ) VALUES (org_a, other_revision_id, other_job_id, 'PENDING')
    RETURNING id INTO other_verification_id;
    UPDATE document_verifications
    SET status = 'VERIFIED', verified_by = user_a, verified_at = clock_timestamp()
    WHERE id IN (verification_id_value, other_verification_id);
    UPDATE document_revisions
    SET status = 'VERIFIED', verified_at = clock_timestamp()
    WHERE id IN (revision_id_value, other_revision_id);
    INSERT INTO batch_documents(organization_id, batch_id, document_id, attached_by)
    VALUES (org_a, batch_a, document_id_value, user_a);

    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by,
        check_number, status, idempotency_key, started_at
    ) VALUES (
        org_a, batch_a, market_id_value, user_a,
        1, 'PROCESSING', 'check-pass', now()
    ) RETURNING id INTO check_pass;

    BEGIN
        INSERT INTO compliance_checks(
            organization_id, batch_id, market_id, created_by, check_number
        ) VALUES (org_b, batch_a, market_id_value, user_b, 1);
        RAISE EXCEPTION 'Cross-tenant compliance check/batch link was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO compliance_checks(
            organization_id, batch_id, market_id, created_by,
            check_number, idempotency_key
        ) VALUES (org_a, batch_a, market_id_value, user_a, 99, 'check-pass');
        RAISE EXCEPTION 'Duplicate compliance check idempotency key was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO compliance_checks(
            organization_id, batch_id, market_id, created_by,
            parent_check_id, check_number
        ) VALUES (
            org_a, batch_a_other, market_id_value, user_a, check_pass, 1
        );
        RAISE EXCEPTION 'Re-check parent from another batch was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO compliance_check_documents(
            organization_id, check_id, document_id, document_revision_id,
            document_file_id, extraction_job_id, verification_id,
            document_checksum_snapshot, file_checksum_snapshot
        ) VALUES (
            org_a, check_pass, document_id_value, revision_id_value,
            other_file_id, job_id_value, verification_id_value, hash_value, hash_value
        );
        RAISE EXCEPTION 'Snapshot file from another revision was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO compliance_check_documents(
            organization_id, check_id, document_id, document_revision_id,
            document_file_id, extraction_job_id, verification_id,
            document_checksum_snapshot, file_checksum_snapshot
        ) VALUES (
            org_a, check_pass, document_id_value, revision_id_value,
            file_id_value, job_id_value, other_verification_id, hash_value, hash_value
        );
        RAISE EXCEPTION 'Snapshot verification from another revision was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO compliance_check_documents(
            organization_id, check_id, document_id, document_revision_id,
            document_file_id, extraction_job_id, verification_id,
            document_checksum_snapshot, file_checksum_snapshot
        ) VALUES (
            org_b, check_pass, document_id_value, revision_id_value,
            file_id_value, job_id_value, verification_id_value, hash_value, hash_value
        );
        RAISE EXCEPTION 'Cross-tenant compliance evidence snapshot was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO compliance_check_documents(
        organization_id, check_id, document_id, document_revision_id,
        document_file_id, extraction_job_id, verification_id,
        document_checksum_snapshot, file_checksum_snapshot
    ) VALUES (
        org_a, check_pass, document_id_value, revision_id_value,
        file_id_value, job_id_value, verification_id_value, hash_value, hash_value
    );

    INSERT INTO compliance_check_legal_versions(
        organization_id, check_id, legal_document_version_id
    ) VALUES (org_a, check_pass, legal_version_id_value);

    INSERT INTO rule_executions(
        organization_id, check_id, rule_version_id, status, outcome,
        actual_value_numeric, actual_unit_id, actual_normalized_value,
        actual_normalized_unit_id, expected_value_numeric, expected_unit_id,
        expected_normalized_value, expected_normalized_unit_id,
        input_reference, started_at, completed_at
    ) VALUES (
        org_a, check_pass, rule_version_id_value, 'COMPLETED', 'PASS',
        0.5, ppm_id, 0.5, canonical_unit_id, 1, ppm_id, 1, canonical_unit_id,
        '{"result_qualifier":"EXACT"}'::jsonb, now(), now()
    ) RETURNING id INTO pass_execution_id;

    IF EXISTS (SELECT 1 FROM findings WHERE rule_execution_id = pass_execution_id) THEN
        RAISE EXCEPTION 'PASS execution unexpectedly created a finding';
    END IF;

    BEGIN
        INSERT INTO rule_executions(
            organization_id, check_id, rule_version_id, status, outcome,
            actual_value_numeric, actual_unit_id, actual_normalized_value,
            actual_normalized_unit_id
        ) VALUES (
            org_a, check_pass, rule_version_id_value, 'COMPLETED', 'REVIEW_REQUIRED',
            1, mass_unit_id, 1, canonical_unit_id
        );
        RAISE EXCEPTION 'Cross-dimension execution normalization was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    SELECT scope_record.id INTO selected_scope_id
    FROM requirement_scopes scope_record
    WHERE scope_record.requirement_id = requirement_id_value
      AND (scope_record.product_id IS NULL OR scope_record.product_id = product_id_value)
      AND (scope_record.product_form_id IS NULL OR scope_record.product_form_id = form_id_value)
      AND (scope_record.market_id IS NULL OR scope_record.market_id = market_id_value)
    ORDER BY scope_record.priority DESC,
      ((scope_record.product_id IS NOT NULL)::int
       + (scope_record.product_form_id IS NOT NULL)::int
       + (scope_record.hs_code_id IS NOT NULL)::int
       + (scope_record.origin_country_id IS NOT NULL)::int
       + (scope_record.destination_country_id IS NOT NULL)::int
       + (scope_record.market_id IS NOT NULL)::int) DESC,
      scope_record.id
    LIMIT 1;
    IF NOT EXISTS (
        SELECT 1 FROM requirement_scopes
        WHERE id = selected_scope_id
          AND product_id IS NOT NULL
          AND product_form_id IS NOT NULL
          AND market_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Specific scope did not outrank wildcard scope';
    END IF;

    SELECT count(*) INTO tie_count
    FROM requirement_scopes scope_record
    WHERE scope_record.requirement_id = requirement_id_value
      AND scope_record.product_id = product_id_value
      AND scope_record.product_form_id = form_id_value
      AND scope_record.market_id = market_id_value
      AND scope_record.priority = 0;
    IF tie_count <> 2 THEN
        RAISE EXCEPTION 'Unresolved scope tie fixture was not preserved';
    END IF;

    IF (SELECT count(*) FROM compliance_rule_versions
        WHERE rule_id = rule_id_value AND status = 'ACTIVE'
          AND (effective_from IS NULL OR effective_from <= DATE '2026-08-11')
          AND (effective_to IS NULL OR effective_to >= DATE '2026-08-11')) <> 1 THEN
        RAISE EXCEPTION 'Inactive/out-of-date rule was selected';
    END IF;

    INSERT INTO registered_export_entities(
        entity_type, registry_namespace, registry_code, name, country_id
    ) VALUES (
        'GROWING_AREA', 'TEST_CHECK_REGISTRY', 'TEST-CHECK-ENTITY',
        'TEST Check Entity', vn_id
    ) RETURNING id INTO entity_id_value;
    INSERT INTO batch_registered_entities(
        organization_id, batch_id, registered_entity_id, entity_role
    ) VALUES (org_a, batch_a, entity_id_value, 'GROWER');
    INSERT INTO market_entity_approvals(
        registered_entity_id, market_id, authority_id,
        source_version_id, legal_citation_id, approval_status,
        valid_from, valid_to
    ) VALUES (
        entity_id_value, market_id_value, authority_id_value,
        legal_version_id_value, citation_id_value, 'APPROVED',
        DATE '2026-01-01', DATE '2026-12-31'
    );
    INSERT INTO market_entity_approvals(
        registered_entity_id, market_id, authority_id,
        source_version_id, legal_citation_id, approval_status,
        valid_from, valid_to
    ) VALUES (
        entity_id_value, market_id_value, authority_id_value,
        legal_version_id_value, citation_id_value, 'EXPIRED',
        DATE '2025-01-01', DATE '2025-12-31'
    );
    IF (SELECT count(*)
        FROM batch_registered_entities batch_entity
        JOIN market_entity_approvals approval
          ON approval.registered_entity_id = batch_entity.registered_entity_id
         AND approval.market_id = market_id_value
        WHERE batch_entity.organization_id = org_a
          AND batch_entity.batch_id = batch_a
          AND approval.approval_status = 'APPROVED'
          AND DATE '2026-08-11' BETWEEN approval.valid_from AND coalesce(approval.valid_to, DATE '9999-12-31')) <> 1 THEN
        RAISE EXCEPTION 'Deterministic registry validity resolution failed';
    END IF;

    -- Clone required immutable snapshots for the remaining aggregation fixtures.
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number, status, idempotency_key, started_at
    ) VALUES (org_a, batch_a, market_id_value, user_a, 2, 'PROCESSING', 'check-non', now())
    RETURNING id INTO check_noncompliant;
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number, status, idempotency_key, started_at
    ) VALUES (org_a, batch_a, market_id_value, user_a, 3, 'PROCESSING', 'check-action', now())
    RETURNING id INTO check_action;
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number, status, idempotency_key, started_at
    ) VALUES (org_a, batch_a, market_id_value, user_a, 4, 'PROCESSING', 'check-review', now())
    RETURNING id INTO check_review;

    INSERT INTO compliance_check_documents(
        organization_id, check_id, document_id, document_revision_id,
        document_file_id, extraction_job_id, verification_id,
        document_checksum_snapshot, file_checksum_snapshot
    ) SELECT org_a, check_record, document_id_value, revision_id_value,
             file_id_value, job_id_value, verification_id_value, hash_value, hash_value
      FROM unnest(ARRAY[check_noncompliant, check_action, check_review]) check_record;
    INSERT INTO compliance_check_legal_versions(
        organization_id, check_id, legal_document_version_id
    ) SELECT org_a, check_record, legal_version_id_value
      FROM unnest(ARRAY[check_noncompliant, check_action, check_review]) check_record;

    INSERT INTO rule_executions(
        organization_id, check_id, rule_version_id, status, outcome,
        actual_normalized_value, actual_value_numeric, actual_unit_id,
        actual_normalized_unit_id, expected_normalized_value,
        expected_value_numeric, expected_unit_id, expected_normalized_unit_id
    ) VALUES (
        org_a, check_noncompliant, rule_version_id_value, 'COMPLETED', 'FAIL',
        2, 2, ppm_id, canonical_unit_id, 1, 1, ppm_id, canonical_unit_id
    ) RETURNING id INTO fail_execution_id;
    INSERT INTO rule_executions(
        organization_id, check_id, rule_version_id, status, outcome
    ) VALUES (org_a, check_action, rule_version_id_value, 'COMPLETED', 'FAIL')
    RETURNING id INTO action_execution_id;
    INSERT INTO rule_executions(
        organization_id, check_id, rule_version_id, status, outcome,
        actual_value_text, input_reference, error_code
    ) VALUES (
        org_a, check_review, rule_version_id_value, 'COMPLETED', 'REVIEW_REQUIRED',
        'ND', '{"result_qualifier":"NOT_DETECTED","numeric_value":null}'::jsonb,
        'AMBIGUOUS_RULE'
    ) RETURNING id INTO review_execution_id;

    INSERT INTO findings(
        organization_id, check_id, rule_execution_id, source_type,
        finding_type, title, description, severity, validation_status
    ) VALUES (
        org_a, check_noncompliant, fail_execution_id, 'RULE_ENGINE',
        'NUMERIC_LIMIT_FAILURE', 'TEST hard failure', 'TEST validated hard failure',
        'HIGH', 'VALIDATED'
    ) RETURNING id INTO high_finding_id;
    INSERT INTO finding_citations(finding_id, citation_id, is_primary)
    VALUES (high_finding_id, citation_id_value, true);

    INSERT INTO findings(
        organization_id, check_id, rule_execution_id, source_type,
        finding_type, title, description, severity, validation_status
    ) VALUES (
        org_a, check_action, action_execution_id, 'RULE_ENGINE',
        'FIXABLE_DEFICIENCY', 'TEST fixable issue', 'TEST action issue',
        'MEDIUM', 'VALIDATED'
    ) RETURNING id INTO action_finding_id;
    INSERT INTO finding_citations(finding_id, citation_id, is_primary)
    VALUES (action_finding_id, citation_id_value, true);

    INSERT INTO findings(
        organization_id, check_id, rule_execution_id, source_type,
        finding_type, title, description, severity, validation_status
    ) VALUES (
        org_a, check_review, review_execution_id, 'RULE_ENGINE',
        'AMBIGUOUS_RULE', 'TEST ambiguous rule', 'TEST requires review',
        'MEDIUM', 'MANUAL_REVIEW_REQUIRED'
    ) RETURNING id INTO review_finding_id;
    INSERT INTO findings(
        organization_id, check_id, rule_execution_id, source_type,
        finding_type, title, description, severity, validation_status
    ) VALUES (
        org_a, check_review, NULL, 'MANUAL',
        'MANUAL_NOTE', 'TEST manual note', 'TEST manual finding',
        'INFO', 'MANUAL_REVIEW_REQUIRED'
    ) RETURNING id INTO manual_finding_id;

    BEGIN
        INSERT INTO findings(
            organization_id, check_id, rule_execution_id, source_type,
            finding_type, title, description, severity, validation_status
        ) VALUES (
            org_a, check_review, NULL, 'RULE_ENGINE',
            'INVALID', 'Invalid', 'Invalid source combination', 'LOW', 'REJECTED'
        );
        RAISE EXCEPTION 'Invalid RULE_ENGINE finding source combination was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO findings(
            organization_id, check_id, rule_execution_id, source_type,
            finding_type, title, description, severity, validation_status
        ) VALUES (
            org_a, check_review, review_execution_id, 'RULE_ENGINE',
            'UNCITED_VALIDATED', 'Uncited validated finding',
            'This fixture must be rejected', 'HIGH', 'VALIDATED'
        );
        SET CONSTRAINTS trg_validated_finding_requires_citation IMMEDIATE;
        RAISE EXCEPTION 'Validated finding without citation was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
    SET CONSTRAINTS trg_validated_finding_requires_citation DEFERRED;

    IF (SELECT actual_value_numeric FROM rule_executions WHERE id = review_execution_id) IS NOT NULL
       OR (SELECT input_reference->>'result_qualifier' FROM rule_executions WHERE id = review_execution_id) <> 'NOT_DETECTED' THEN
        RAISE EXCEPTION 'NOT_DETECTED execution was converted to zero';
    END IF;
    IF derive_compliance_overall_result(check_pass) <> 'COMPLIANT'
       OR derive_compliance_overall_result(check_noncompliant) <> 'NON_COMPLIANT'
       OR derive_compliance_overall_result(check_action) <> 'ACTION_REQUIRED'
       OR derive_compliance_overall_result(check_review) <> 'MANUAL_REVIEW_REQUIRED' THEN
        RAISE EXCEPTION 'Deterministic overall result aggregation failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM findings finding_record
        JOIN finding_citations finding_citation ON finding_citation.finding_id = finding_record.id
        JOIN legal_citations citation_record ON citation_record.id = finding_citation.citation_id
        JOIN legal_sections section_record ON section_record.id = citation_record.section_id
        JOIN legal_document_versions version_record ON version_record.id = section_record.version_id
        JOIN compliance_check_legal_versions snapshot
          ON snapshot.check_id = finding_record.check_id
         AND snapshot.legal_document_version_id = version_record.id
        WHERE finding_record.id = high_finding_id
    ) THEN
        RAISE EXCEPTION 'Finding citation did not resolve through snapshotted legal provenance';
    END IF;

    UPDATE compliance_checks
    SET status = 'COMPLETED', overall_result = 'COMPLIANT', completed_at = clock_timestamp()
    WHERE id = check_pass;
    UPDATE compliance_checks
    SET status = 'COMPLETED', overall_result = 'NON_COMPLIANT', completed_at = clock_timestamp()
    WHERE id = check_noncompliant;
    UPDATE compliance_checks
    SET status = 'COMPLETED', overall_result = 'ACTION_REQUIRED', completed_at = clock_timestamp()
    WHERE id = check_action;
    UPDATE compliance_checks
    SET status = 'COMPLETED', overall_result = 'MANUAL_REVIEW_REQUIRED', completed_at = clock_timestamp()
    WHERE id = check_review;

    BEGIN
        UPDATE rule_executions SET actual_value_text = 'REWRITTEN' WHERE id = pass_execution_id;
        RAISE EXCEPTION 'Completed check execution was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        UPDATE findings SET description = 'REWRITTEN' WHERE id = high_finding_id;
        RAISE EXCEPTION 'Completed check finding was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        DELETE FROM finding_citations
        WHERE finding_id = high_finding_id AND citation_id = citation_id_value;
        RAISE EXCEPTION 'Completed check finding citation was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        DELETE FROM compliance_check_legal_versions
        WHERE check_id = check_pass AND legal_document_version_id = legal_version_id_value;
        RAISE EXCEPTION 'Completed legal snapshot was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        UPDATE compliance_check_documents SET purpose = 'REWRITTEN' WHERE check_id = check_pass;
        RAISE EXCEPTION 'Completed evidence snapshot was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    INSERT INTO compliance_check_events(
        organization_id, check_id, event_type, actor_type, metadata
    ) VALUES (org_a, check_pass, 'CHECK_COMPLETED', 'SYSTEM', '{"test":true}'::jsonb);
    BEGIN
        UPDATE compliance_check_events SET event_type = 'REWRITTEN' WHERE check_id = check_pass;
        RAISE EXCEPTION 'Compliance event history was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by,
        parent_check_id, check_number, status, idempotency_key
    ) VALUES (
        org_a, batch_a, market_id_value, user_a,
        check_pass, 5, 'QUEUED', 'recheck-pass'
    ) RETURNING id INTO recheck_id_value;
    IF NOT EXISTS (
        SELECT 1 FROM compliance_checks
        WHERE id = check_pass AND status = 'COMPLETED' AND overall_result = 'COMPLIANT'
    ) OR NOT EXISTS (
        SELECT 1 FROM compliance_checks
        WHERE id = recheck_id_value AND parent_check_id = check_pass AND status = 'QUEUED'
    ) THEN
        RAISE EXCEPTION 'Re-check did not preserve independent completed history';
    END IF;

    INSERT INTO legal_document_versions(
        legal_document_id, version_number, previous_version_id, status, content_hash
    ) VALUES (
        legal_document_id_value, 2, legal_version_id_value, 'DRAFT', repeat('8', 64)
    ) RETURNING id INTO new_legal_version_id;
    IF NOT EXISTS (
        SELECT 1 FROM compliance_check_legal_versions
        WHERE check_id = check_pass AND legal_document_version_id = legal_version_id_value
    ) OR EXISTS (
        SELECT 1 FROM compliance_check_legal_versions
        WHERE check_id = check_pass AND legal_document_version_id = new_legal_version_id
    ) THEN
        RAISE EXCEPTION 'New legal version changed historical check snapshot';
    END IF;
END $$;

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

ROLLBACK;

SELECT 'phase 06 deterministic compliance engine assertions passed' AS result;
