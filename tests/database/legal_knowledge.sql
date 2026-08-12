BEGIN;

DO $$
DECLARE
    source_id_value uuid;
    authority_id_value uuid;
    legal_document_one uuid;
    legal_document_two uuid;
    version_one uuid;
    version_two uuid;
    other_version uuid;
    article_id uuid;
    clause_id uuid;
    point_id uuid;
    other_section_id uuid;
    requirement_one uuid;
    requirement_two uuid;
    citation_id_value uuid;
    legal_file_id_value uuid;
    wildcard_scope_id uuid;
    parameter_id_value uuid;
    legal_limit_id_value uuid;
    substance_id_value uuid;
    entity_id_value uuid;
    vn_id uuid;
    market_id_value uuid;
    durian_id uuid;
    fresh_form_id uuid;
    other_product_id uuid;
    other_form_id uuid;
    mg_per_kg_id uuid;
    ppm_id uuid;
    kg_id uuid;
    user_id_value uuid;
    organization_id_value uuid;
    document_type_value uuid;
    tenant_document_id uuid;
    tenant_revision_id uuid;
    lab_result_id uuid;
    hash_one text := repeat('d', 64);
BEGIN
    SELECT id INTO vn_id FROM countries WHERE iso2_code = 'VN';
    SELECT id INTO market_id_value FROM markets WHERE code = 'CN_GACC';
    SELECT id INTO durian_id FROM products WHERE code = 'DURIAN';
    SELECT id INTO fresh_form_id
    FROM product_forms WHERE product_id = durian_id AND code = 'FRESH';
    SELECT id INTO mg_per_kg_id FROM measurement_units WHERE code = 'MG_PER_KG';
    SELECT id INTO ppm_id FROM measurement_units WHERE code = 'PPM';
    SELECT id INTO kg_id FROM measurement_units WHERE code = 'KG';

    INSERT INTO legal_sources(
        name, source_type, base_url, country_id, is_official, trust_level, status
    ) VALUES (
        'TEST FIXTURE Official Source', 'OFFICIAL_PUBLICATION',
        'https://example.invalid/legal', vn_id, true, 'PRIMARY', 'ACTIVE'
    ) RETURNING id INTO source_id_value;

    INSERT INTO legal_authorities(
        country_id, code, name, authority_type, official_url
    ) VALUES (
        vn_id, 'TEST_AUTHORITY', 'TEST FIXTURE Authority',
        'TEST_AUTHORITY_TYPE', 'https://example.invalid/authority'
    ) RETURNING id INTO authority_id_value;

    INSERT INTO legal_documents(
        source_id, document_code, title, document_type,
        jurisdiction_type, language_code, current_status
    ) VALUES (
        source_id_value, 'TEST-DOC-1', 'TEST FIXTURE Legal Document One',
        'REGULATION', 'NATIONAL', 'en', 'DRAFT'
    ) RETURNING id INTO legal_document_one;
    INSERT INTO legal_documents(
        source_id, document_code, title, document_type,
        jurisdiction_type, language_code, current_status
    ) VALUES (
        source_id_value, 'TEST-DOC-2', 'TEST FIXTURE Legal Document Two',
        'REGULATION', 'NATIONAL', 'en', 'DRAFT'
    ) RETURNING id INTO legal_document_two;

    INSERT INTO legal_document_parties(legal_document_id, authority_id, party_role)
    VALUES (legal_document_one, authority_id_value, 'ISSUING_AUTHORITY');

    INSERT INTO legal_document_versions(
        legal_document_id, version_number, version_label,
        effective_from, status, content_hash
    ) VALUES (
        legal_document_one, 1, 'TEST VERSION 1', DATE '2026-01-01',
        'UNDER_REVIEW', hash_one
    ) RETURNING id INTO version_one;

    BEGIN
        INSERT INTO legal_document_versions(legal_document_id, version_number, status)
        VALUES (legal_document_one, 1, 'DRAFT');
        RAISE EXCEPTION 'Duplicate legal document version number was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO legal_document_versions(
        legal_document_id, version_number, status
    ) VALUES (legal_document_two, 1, 'DRAFT')
    RETURNING id INTO other_version;

    BEGIN
        INSERT INTO legal_document_versions(
            legal_document_id, version_number, previous_version_id, status
        ) VALUES (legal_document_two, 2, version_one, 'DRAFT');
        RAISE EXCEPTION 'Previous legal version from another document was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO legal_document_versions(
            legal_document_id, version_number, effective_from, effective_to, status
        ) VALUES (
            legal_document_one, 99, DATE '2026-12-31', DATE '2026-01-01', 'DRAFT'
        );
        RAISE EXCEPTION 'Invalid legal version effective range was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO legal_document_files(
        version_id, file_name, mime_type, storage_provider, bucket_name,
        storage_path, language_code, checksum_sha256, is_original, page_count
    ) VALUES (
        version_one, 'test-legal.pdf', 'application/pdf', 'SUPABASE', 'legal-private',
        'legal/test/version-1/source.pdf', 'en', hash_one, true, 10
    ) RETURNING id INTO legal_file_id_value;

    INSERT INTO legal_sections(
        version_id, section_type, section_number, title, content,
        order_index, page_start, page_end
    ) VALUES (
        version_one, 'ARTICLE', '1', 'TEST Article', 'TEST fixture article content',
        1, 1, 2
    ) RETURNING id INTO article_id;
    INSERT INTO legal_sections(
        version_id, parent_id, section_type, section_number, content, order_index,
        page_start, page_end
    ) VALUES (
        version_one, article_id, 'CLAUSE', '1', 'TEST fixture clause content',
        2, 1, 1
    ) RETURNING id INTO clause_id;
    INSERT INTO legal_sections(
        version_id, parent_id, section_type, section_number, content, order_index,
        page_start, page_end
    ) VALUES (
        version_one, clause_id, 'POINT', 'a', 'TEST fixture point content',
        3, 1, 1
    ) RETURNING id INTO point_id;

    INSERT INTO legal_sections(
        version_id, section_type, content, order_index
    ) VALUES (other_version, 'ARTICLE', 'Other version test section', 1)
    RETURNING id INTO other_section_id;

    BEGIN
        INSERT INTO legal_sections(
            version_id, parent_id, section_type, content, order_index
        ) VALUES (other_version, article_id, 'CLAUSE', 'Cross-version parent', 2);
        RAISE EXCEPTION 'Cross-version legal section parent was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO legal_sections(
            version_id, section_type, content, order_index, page_start, page_end
        ) VALUES (version_one, 'OTHER', 'Invalid pages', 9, 5, 4);
        RAISE EXCEPTION 'Invalid legal section page range was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO legal_requirements(
        section_id, requirement_code, title, requirement_text,
        requirement_type, obligation_level, validation_type,
        severity_default, effective_from, status
    ) VALUES (
        point_id, 'TEST-REQ-001', 'TEST requirement one',
        'TEST fixture requirement text', 'PESTICIDE_RESIDUE', 'MUST',
        'NUMERIC_LIMIT', 'HIGH', DATE '2026-01-01', 'ACTIVE'
    ) RETURNING id INTO requirement_one;

    INSERT INTO legal_requirements(
        section_id, requirement_code, title, requirement_text,
        requirement_type, obligation_level, validation_type,
        severity_default, status
    ) VALUES (
        clause_id, 'TEST-REQ-002', 'TEST requirement two',
        'TEST fixture second requirement', 'REGISTRATION', 'MUST',
        'REGISTRY_LOOKUP', 'MEDIUM', 'ACTIVE'
    ) RETURNING id INTO requirement_two;

    BEGIN
        INSERT INTO legal_requirements(
            section_id, requirement_code, title, requirement_text,
            requirement_type, obligation_level, validation_type, severity_default
        ) VALUES (
            NULL, 'TEST-REQ-NO-SECTION', 'No section', 'No section',
            'OTHER', 'MUST', 'OTHER', 'LOW'
        );
        RAISE EXCEPTION 'Legal requirement without a section was accepted';
    EXCEPTION WHEN not_null_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO legal_requirements(
            section_id, requirement_code, title, requirement_text,
            requirement_type, obligation_level, validation_type,
            severity_default, effective_from, effective_to
        ) VALUES (
            point_id, 'TEST-REQ-BAD-DATE', 'Bad dates', 'Bad dates',
            'OTHER', 'MUST', 'OTHER', 'LOW', DATE '2026-12-31', DATE '2026-01-01'
        );
        RAISE EXCEPTION 'Invalid requirement effective range was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO requirement_scopes(requirement_id, priority)
    VALUES (requirement_one, 0) RETURNING id INTO wildcard_scope_id;
    INSERT INTO requirement_scopes(
        requirement_id, product_id, product_form_id, market_id, priority
    ) VALUES (requirement_one, durian_id, fresh_form_id, market_id_value, 10);

    IF (SELECT count(*) FROM requirement_scopes WHERE requirement_id = requirement_one) <> 2
       OR NOT EXISTS (
           SELECT 1 FROM requirement_scopes
           WHERE requirement_id = requirement_one
             AND product_id IS NULL AND product_form_id IS NULL
             AND hs_code_id IS NULL AND origin_country_id IS NULL
             AND destination_country_id IS NULL AND market_id IS NULL
       ) THEN
        RAISE EXCEPTION 'Multiple scopes or wildcard NULL scope semantics fixture failed';
    END IF;

    INSERT INTO products(code, name_vi, name_en, category)
    VALUES ('LEGAL_TEST_OTHER', 'Test other', 'Test other', 'TEST')
    RETURNING id INTO other_product_id;
    INSERT INTO product_forms(product_id, code, name_vi, name_en)
    VALUES (other_product_id, 'LEGAL_OTHER_FORM', 'Test form', 'Test form')
    RETURNING id INTO other_form_id;

    BEGIN
        INSERT INTO requirement_scopes(requirement_id, product_id, product_form_id)
        VALUES (requirement_one, durian_id, other_form_id);
        RAISE EXCEPTION 'Inconsistent requirement product/form scope was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO requirement_parameters(
        requirement_id, parameter_code, operator, value_numeric,
        unit_id, normalized_value_numeric, normalized_unit_id
    ) VALUES (
        requirement_one, 'TEST_THRESHOLD', 'LTE', 1,
        ppm_id, 1, mg_per_kg_id
    ) RETURNING id INTO parameter_id_value;

    BEGIN
        INSERT INTO requirement_parameters(
            requirement_id, parameter_code, operator, value_numeric,
            unit_id, normalized_value_numeric, normalized_unit_id
        ) VALUES (
            requirement_one, 'BAD_DIMENSION', 'LTE', 1,
            kg_id, 1, mg_per_kg_id
        );
        RAISE EXCEPTION 'Incompatible normalized parameter unit was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO requirement_parameters(
            requirement_id, parameter_code, operator, value_numeric,
            unit_id, normalized_value_numeric, normalized_unit_id
        ) VALUES (
            requirement_one, 'NON_CANONICAL', 'LTE', 1,
            mg_per_kg_id, 1, ppm_id
        );
        RAISE EXCEPTION 'Non-canonical normalized parameter unit was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO regulated_substances(
        code, name, substance_type, cas_number, aliases
    ) VALUES (
        'TEST-SUBSTANCE', 'TEST FIXTURE Substance', 'PESTICIDE',
        'TEST-CAS', '["TEST ALIAS"]'::jsonb
    ) RETURNING id INTO substance_id_value;

    INSERT INTO users(email, full_name, status)
    VALUES ('legal-lab@example.com', 'Legal Lab Test User', 'ACTIVE')
    RETURNING id INTO user_id_value;
    INSERT INTO organizations(name, created_by)
    VALUES ('Legal Lab Test Org', user_id_value) RETURNING id INTO organization_id_value;
    SELECT id INTO document_type_value FROM document_types WHERE code = 'LAB_REPORT';
    INSERT INTO documents(organization_id, document_type_id, title, created_by)
    VALUES (organization_id_value, document_type_value, 'TEST lab evidence', user_id_value)
    RETURNING id INTO tenant_document_id;
    INSERT INTO document_revisions(
        organization_id, document_id, revision_number, status, created_by
    ) VALUES (organization_id_value, tenant_document_id, 1, 'DRAFT', user_id_value)
    RETURNING id INTO tenant_revision_id;
    INSERT INTO lab_test_results(
        organization_id, document_revision_id, analyte_name_raw,
        analyte_name_normalized, result_value, result_qualifier,
        unit_id, regulated_substance_id
    ) VALUES (
        organization_id_value, tenant_revision_id, 'test raw analyte',
        'TEST NORMALIZED ANALYTE', 0.1, 'EXACT', ppm_id, substance_id_value
    ) RETURNING id INTO lab_result_id;

    IF NOT EXISTS (
        SELECT 1 FROM lab_test_results
        WHERE id = lab_result_id
          AND regulated_substance_id = substance_id_value
          AND analyte_name_raw = 'test raw analyte'
          AND analyte_name_normalized = 'TEST NORMALIZED ANALYTE'
    ) THEN
        RAISE EXCEPTION 'Lab substance mapping did not preserve analyte names';
    END IF;

    BEGIN
        UPDATE lab_test_results SET regulated_substance_id = gen_random_uuid()
        WHERE id = lab_result_id;
        RAISE EXCEPTION 'Invalid regulated substance FK was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO legal_limits(
        requirement_id, substance_id, product_id, product_form_id, market_id,
        limit_type, operator, limit_value, unit_id,
        normalized_limit_value, normalized_unit_id,
        effective_from, status
    ) VALUES (
        requirement_one, substance_id_value, durian_id, fresh_form_id, market_id_value,
        'MRL', 'LTE', 1, ppm_id, 1, mg_per_kg_id,
        DATE '2026-01-01', 'ACTIVE'
    ) RETURNING id INTO legal_limit_id_value;

    BEGIN
        INSERT INTO legal_limits(
            requirement_id, limit_type, operator, limit_value, unit_id,
            normalized_limit_value, normalized_unit_id, effective_from
        ) VALUES (
            gen_random_uuid(), 'OTHER', 'LTE', 1, ppm_id,
            1, mg_per_kg_id, DATE '2026-01-01'
        );
        RAISE EXCEPTION 'Legal limit without requirement provenance was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO legal_limits(
            requirement_id, limit_type, operator, limit_value, unit_id,
            normalized_limit_value, normalized_unit_id, effective_from
        ) VALUES (
            requirement_one, 'MRL', 'LTE', -1, ppm_id,
            -1, mg_per_kg_id, DATE '2026-01-01'
        );
        RAISE EXCEPTION 'Negative legal limit was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO legal_limits(
            requirement_id, limit_type, operator, limit_value, unit_id,
            normalized_limit_value, normalized_unit_id, effective_from, effective_to
        ) VALUES (
            requirement_one, 'MRL', 'LTE', 1, ppm_id,
            1, mg_per_kg_id, DATE '2026-12-31', DATE '2026-01-01'
        );
        RAISE EXCEPTION 'Invalid legal limit effective range was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO legal_limits(
            requirement_id, limit_type, operator, limit_value, unit_id,
            normalized_limit_value, normalized_unit_id, effective_from
        ) VALUES (
            requirement_one, 'MRL', 'LTE', 1, kg_id,
            1, mg_per_kg_id, DATE '2026-01-01'
        );
        RAISE EXCEPTION 'Incompatible legal limit units were accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO legal_citations(
            version_id, section_id, citation_code, display_label
        ) VALUES (version_one, NULL, 'NO-SECTION', 'No section');
        RAISE EXCEPTION 'Citation without section was accepted';
    EXCEPTION WHEN not_null_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO legal_citations(
            version_id, section_id, requirement_id, citation_code, display_label
        ) VALUES (
            version_one, article_id, requirement_two,
            'BAD-REQ-SECTION', 'Bad requirement section'
        );
        RAISE EXCEPTION 'Citation with requirement from another section was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO legal_citations(
        version_id, section_id, requirement_id, citation_code,
        display_label, quote_excerpt, canonical_reference
    ) VALUES (
        version_one, point_id, requirement_one, 'TEST-CITATION-1',
        'TEST Document 1, Point a', 'TEST fixture excerpt', 'test://document/1/point/a'
    ) RETURNING id INTO citation_id_value;

    IF NOT EXISTS (
        SELECT 1
        FROM legal_citations citation_record
        JOIN legal_sections section_record ON section_record.id = citation_record.section_id
        JOIN legal_document_versions version_record ON version_record.id = section_record.version_id
        JOIN legal_documents document_record ON document_record.id = version_record.legal_document_id
        JOIN legal_sources source_record ON source_record.id = document_record.source_id
        WHERE citation_record.id = citation_id_value
          AND source_record.id = source_id_value
    ) THEN
        RAISE EXCEPTION 'Citation provenance chain could not be resolved';
    END IF;

    UPDATE legal_document_versions SET status = 'APPROVED' WHERE id = version_one;

    BEGIN
        UPDATE legal_document_versions SET content_hash = repeat('e', 64) WHERE id = version_one;
        RAISE EXCEPTION 'Approved legal version provenance was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE legal_sections SET content = 'REWRITTEN' WHERE id = point_id;
        RAISE EXCEPTION 'Approved legal section was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE legal_document_files SET file_name = 'rewritten.pdf' WHERE id = legal_file_id_value;
        RAISE EXCEPTION 'Original legal source file was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE legal_requirements SET requirement_text = 'REWRITTEN' WHERE id = requirement_one;
        RAISE EXCEPTION 'Approved legal requirement was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE requirement_scopes SET priority = 999 WHERE id = wildcard_scope_id;
        RAISE EXCEPTION 'Approved requirement scope was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE requirement_parameters SET value_numeric = 999 WHERE id = parameter_id_value;
        RAISE EXCEPTION 'Approved requirement parameter was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE legal_limits SET limit_value = 999 WHERE id = legal_limit_id_value;
        RAISE EXCEPTION 'Approved legal limit was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE legal_citations SET display_label = 'REWRITTEN' WHERE id = citation_id_value;
        RAISE EXCEPTION 'Approved legal citation was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    UPDATE legal_document_versions SET status = 'ACTIVE' WHERE id = version_one;
    INSERT INTO legal_document_versions(
        legal_document_id, version_number, previous_version_id,
        version_label, status, content_hash
    ) VALUES (
        legal_document_one, 2, version_one, 'TEST VERSION 2', 'DRAFT', repeat('f', 64)
    ) RETURNING id INTO version_two;

    INSERT INTO registered_export_entities(
        entity_type, registry_namespace, registry_code, name, country_id
    ) VALUES (
        'GROWING_AREA', 'TEST_LEGAL_REGISTRY', 'TEST-ENTITY-001',
        'TEST FIXTURE Registry Entity', vn_id
    ) RETURNING id INTO entity_id_value;

    INSERT INTO market_entity_approvals(
        registered_entity_id, market_id, authority_id,
        source_version_id, legal_citation_id, approval_status,
        valid_from, valid_to
    ) VALUES (
        entity_id_value, market_id_value, authority_id_value,
        version_one, citation_id_value, 'APPROVED',
        DATE '2026-01-01', DATE '2026-12-31'
    );

    BEGIN
        INSERT INTO market_entity_approvals(
            registered_entity_id, market_id, authority_id,
            source_version_id, legal_citation_id, approval_status, valid_from
        ) VALUES (
            entity_id_value, market_id_value, authority_id_value,
            version_two, citation_id_value, 'PENDING', DATE '2026-01-01'
        );
        RAISE EXCEPTION 'Market approval citation/version mismatch was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO market_entity_approvals(
            registered_entity_id, market_id, authority_id,
            source_version_id, legal_citation_id, approval_status,
            valid_from, valid_to
        ) VALUES (
            entity_id_value, market_id_value, authority_id_value,
            version_one, citation_id_value, 'APPROVED',
            DATE '2026-12-31', DATE '2026-01-01'
        );
        RAISE EXCEPTION 'Invalid market approval date range was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

ROLLBACK;

SELECT 'phase 05 legal knowledge assertions passed' AS result;
