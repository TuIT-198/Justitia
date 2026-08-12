BEGIN;

DO $$
DECLARE
    user_a uuid;
    user_b uuid;
    org_a uuid;
    org_b uuid;
    document_a uuid;
    document_b uuid;
    revision_a1 uuid;
    revision_a2 uuid;
    revision_b1 uuid;
    file_a1 uuid;
    file_a2 uuid;
    file_b1 uuid;
    job_a1 uuid;
    job_a2 uuid;
    job_b1 uuid;
    field_a uuid;
    exact_result_id uuid;
    nd_result_id uuid;
    verification_a uuid;
    change_a uuid;
    document_type_value uuid;
    mass_fraction_dimension uuid;
    mass_dimension uuid;
    mg_per_kg_unit uuid;
    ppm_unit uuid;
    kg_unit uuid;
    sha_value text := repeat('c', 64);
BEGIN
    SELECT id INTO mass_fraction_dimension
    FROM measurement_dimensions WHERE code = 'MASS_FRACTION';
    SELECT id INTO mass_dimension
    FROM measurement_dimensions WHERE code = 'MASS';
    SELECT id INTO mg_per_kg_unit FROM measurement_units WHERE code = 'MG_PER_KG';
    SELECT id INTO ppm_unit FROM measurement_units WHERE code = 'PPM';
    SELECT id INTO kg_unit FROM measurement_units WHERE code = 'KG';

    IF NOT EXISTS (
        SELECT 1 FROM measurement_units
        WHERE id = ppm_unit AND dimension_id = mass_fraction_dimension
    ) OR NOT EXISTS (
        SELECT 1 FROM measurement_units
        WHERE id = kg_unit AND dimension_id = mass_dimension
    ) THEN
        RAISE EXCEPTION 'Seeded unit belongs to the wrong dimension';
    END IF;

    BEGIN
        INSERT INTO measurement_units(
            dimension_id, code, symbol, conversion_factor, is_canonical
        ) VALUES (mass_fraction_dimension, 'PPM', 'duplicate ppm', 1, false);
        RAISE EXCEPTION 'Duplicate unit code was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO measurement_units(
            dimension_id, code, symbol, conversion_factor, is_canonical
        ) VALUES (mass_fraction_dimension, 'SECOND_CANONICAL_MF', 'mf2', 1, true);
        RAISE EXCEPTION 'Second active canonical unit was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO measurement_units(
            dimension_id, code, symbol, conversion_factor
        ) VALUES (mass_fraction_dimension, 'INVALID_FACTOR', 'bad', 0);
        RAISE EXCEPTION 'Invalid conversion factor was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO users(email, full_name, status)
    VALUES ('ocr-a@example.com', 'OCR User A', 'ACTIVE') RETURNING id INTO user_a;
    INSERT INTO users(email, full_name, status)
    VALUES ('ocr-b@example.com', 'OCR User B', 'ACTIVE') RETURNING id INTO user_b;
    INSERT INTO organizations(name, created_by)
    VALUES ('OCR Org A', user_a) RETURNING id INTO org_a;
    INSERT INTO organizations(name, created_by)
    VALUES ('OCR Org B', user_b) RETURNING id INTO org_b;
    SELECT id INTO document_type_value FROM document_types WHERE code = 'LAB_REPORT';

    INSERT INTO documents(organization_id, document_type_id, title, created_by)
    VALUES (org_a, document_type_value, 'Lab report A', user_a) RETURNING id INTO document_a;
    INSERT INTO documents(organization_id, document_type_id, title, created_by)
    VALUES (org_b, document_type_value, 'Lab report B', user_b) RETURNING id INTO document_b;

    INSERT INTO document_revisions(
        organization_id, document_id, revision_number, status, created_by
    ) VALUES (org_a, document_a, 1, 'DRAFT', user_a) RETURNING id INTO revision_a1;
    INSERT INTO document_revisions(
        organization_id, document_id, revision_number, status, created_by
    ) VALUES (org_b, document_b, 1, 'DRAFT', user_b) RETURNING id INTO revision_b1;

    INSERT INTO document_files(
        organization_id, document_revision_id, storage_provider, bucket_name,
        storage_path, original_file_name, mime_type, file_size_bytes,
        checksum_sha256, uploaded_by
    ) VALUES (
        org_a, revision_a1, 'SUPABASE', 'private-evidence', 'ocr/a/r1.pdf',
        'r1.pdf', 'application/pdf', 100, sha_value, user_a
    ) RETURNING id INTO file_a1;
    INSERT INTO document_files(
        organization_id, document_revision_id, storage_provider, bucket_name,
        storage_path, original_file_name, mime_type, file_size_bytes,
        checksum_sha256, uploaded_by
    ) VALUES (
        org_b, revision_b1, 'SUPABASE', 'private-evidence', 'ocr/b/r1.pdf',
        'r1.pdf', 'application/pdf', 100, sha_value, user_b
    ) RETURNING id INTO file_b1;

    INSERT INTO document_extraction_jobs(
        organization_id, document_revision_id, document_file_id, status,
        extraction_method, provider, model_name, raw_text, raw_output,
        confidence_score, idempotency_key, attempt_number, max_attempts,
        started_at, completed_at
    ) VALUES (
        org_a, revision_a1, file_a1, 'COMPLETED', 'OCR', 'TEST_PROVIDER',
        'test-model', 'Raw OCR evidence', '{"pages":1}'::jsonb,
        0.95, 'ocr-org-a-r1', 1, 3, now(), now()
    ) RETURNING id INTO job_a1;

    INSERT INTO document_extraction_jobs(
        organization_id, document_revision_id, document_file_id,
        extraction_method, idempotency_key
    ) VALUES (org_b, revision_b1, file_b1, 'MANUAL', 'ocr-org-b-r1')
    RETURNING id INTO job_b1;

    BEGIN
        INSERT INTO document_extraction_jobs(
            organization_id, document_revision_id, document_file_id,
            extraction_method
        ) VALUES (org_b, revision_a1, file_a1, 'OCR');
        RAISE EXCEPTION 'Cross-tenant extraction revision/file was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO document_extraction_jobs(
            organization_id, document_revision_id, document_file_id,
            extraction_method
        ) VALUES (org_a, revision_a1, file_b1, 'OCR');
        RAISE EXCEPTION 'File from another revision was accepted by extraction job';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO document_extraction_jobs(
            organization_id, document_revision_id, document_file_id,
            extraction_method, confidence_score
        ) VALUES (org_a, revision_a1, file_a1, 'OCR', 1.1);
        RAISE EXCEPTION 'Invalid extraction confidence was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO document_extraction_jobs(
            organization_id, document_revision_id, document_file_id,
            extraction_method, attempt_number, max_attempts
        ) VALUES (org_a, revision_a1, file_a1, 'OCR', 3, 2);
        RAISE EXCEPTION 'Invalid retry counters were accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO document_extraction_jobs(
            organization_id, document_revision_id, document_file_id,
            extraction_method, idempotency_key
        ) VALUES (org_a, revision_a1, file_a1, 'OCR', 'ocr-org-a-r1');
        RAISE EXCEPTION 'Duplicate tenant idempotency key was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO extracted_fields(
        organization_id, extraction_job_id, field_code, field_label,
        raw_value, normalized_value, data_type, confidence_score, page_number
    ) VALUES (
        org_a, job_a1, 'PUC_CODE', 'Growing area code',
        ' vn-puc 001 ', 'VN-PUC-001', 'CODE', 0.88, 1
    ) RETURNING id INTO field_a;

    IF NOT EXISTS (
        SELECT 1 FROM extracted_fields
        WHERE id = field_a
          AND raw_value = ' vn-puc 001 '
          AND normalized_value = 'VN-PUC-001'
    ) THEN
        RAISE EXCEPTION 'Raw and normalized extracted values were not both retained';
    END IF;

    BEGIN
        INSERT INTO extracted_fields(
            organization_id, extraction_job_id, field_code, data_type
        ) VALUES (org_b, job_a1, 'INVALID', 'TEXT');
        RAISE EXCEPTION 'Cross-tenant extracted field/job link was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO lab_test_results(
        organization_id, document_revision_id, extraction_job_id,
        analyte_name_raw, analyte_name_normalized, result_value,
        result_qualifier, unit_id, normalized_value, normalized_unit_id,
        test_method, confidence_score, page_number
    ) VALUES (
        org_a, revision_a1, job_a1, 'Analyte exact', 'ANALYTE EXACT', 0.5,
        'EXACT', ppm_unit, 0.5, mg_per_kg_unit, 'TEST METHOD', 0.9, 1
    ) RETURNING id INTO exact_result_id;

    INSERT INTO lab_test_results(
        organization_id, document_revision_id, extraction_job_id,
        analyte_name_raw, analyte_name_normalized, result_value,
        result_text, result_qualifier, unit_id
    ) VALUES (
        org_a, revision_a1, job_a1, 'Analyte ND', 'ANALYTE ND', NULL,
        'ND', 'NOT_DETECTED', ppm_unit
    ) RETURNING id INTO nd_result_id;

    IF (SELECT result_value FROM lab_test_results WHERE id = nd_result_id) IS NOT NULL THEN
        RAISE EXCEPTION 'NOT_DETECTED was coerced to a numeric value';
    END IF;

    INSERT INTO lab_test_results(
        organization_id, document_revision_id, analyte_name_raw,
        result_value, result_qualifier, unit_id
    ) VALUES (org_a, revision_a1, 'Analyte less than', 0.01, 'LESS_THAN', ppm_unit);
    INSERT INTO lab_test_results(
        organization_id, document_revision_id, analyte_name_raw,
        result_qualifier, unit_id, detection_limit
    ) VALUES (org_a, revision_a1, 'Analyte below LOD', 'LESS_THAN_LOD', ppm_unit, 0.005);
    INSERT INTO lab_test_results(
        organization_id, document_revision_id, analyte_name_raw,
        result_qualifier, unit_id, quantification_limit
    ) VALUES (org_a, revision_a1, 'Analyte below LOQ', 'LESS_THAN_LOQ', ppm_unit, 0.01);

    BEGIN
        INSERT INTO lab_test_results(
            organization_id, document_revision_id, analyte_name_raw,
            result_qualifier, unit_id, detection_limit
        ) VALUES (org_a, revision_a1, 'Negative LOD', 'LESS_THAN_LOD', ppm_unit, -0.1);
        RAISE EXCEPTION 'Negative LOD was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO lab_test_results(
            organization_id, document_revision_id, analyte_name_raw,
            result_value, result_qualifier, unit_id,
            normalized_value, normalized_unit_id
        ) VALUES (org_a, revision_a1, 'Wrong dimension', 1, 'EXACT', kg_unit, 1, mg_per_kg_unit);
        RAISE EXCEPTION 'Cross-dimension normalization was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO lab_test_results(
            organization_id, document_revision_id, extraction_job_id,
            analyte_name_raw, result_value, result_qualifier
        ) VALUES (org_b, revision_b1, job_a1, 'Cross tenant', 1, 'EXACT');
        RAISE EXCEPTION 'Cross-tenant lab extraction job was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO document_verifications(
        organization_id, document_revision_id, extraction_job_id,
        status, review_notes
    ) VALUES (org_a, revision_a1, job_a1, 'PENDING', 'Awaiting reviewer')
    RETURNING id INTO verification_a;

    BEGIN
        INSERT INTO document_verifications(
            organization_id, document_revision_id, extraction_job_id, status
        ) VALUES (org_b, revision_b1, job_a1, 'PENDING');
        RAISE EXCEPTION 'Cross-tenant verification extraction job was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO document_verification_changes(
        organization_id, verification_id, target_type, target_id,
        field_code, old_value, new_value, change_reason, changed_by
    ) VALUES (
        org_a, verification_a, 'EXTRACTED_FIELD', field_a,
        'PUC_CODE', 'vn-puc 001', 'VN-PUC-001', 'Normalized reviewer correction', user_a
    ) RETURNING id INTO change_a;

    IF NOT EXISTS (
        SELECT 1 FROM document_verification_changes
        WHERE id = change_a
          AND old_value = 'vn-puc 001'
          AND new_value = 'VN-PUC-001'
    ) THEN
        RAISE EXCEPTION 'Verification correction history did not retain old/new values';
    END IF;

    UPDATE document_verifications
    SET status = 'VERIFIED', verified_by = user_a,
        verified_at = clock_timestamp(), updated_at = clock_timestamp()
    WHERE id = verification_a;
    UPDATE document_revisions
    SET status = 'VERIFIED', verified_at = clock_timestamp()
    WHERE id = revision_a1;

    BEGIN
        UPDATE extracted_fields SET normalized_value = 'CHANGED' WHERE id = field_a;
        RAISE EXCEPTION 'Verified extracted field was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        DELETE FROM lab_test_results WHERE id = exact_result_id;
        RAISE EXCEPTION 'Verified lab result was deletable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE document_extraction_jobs SET raw_text = 'OVERWRITTEN' WHERE id = job_a1;
        RAISE EXCEPTION 'Verified raw extraction history was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE document_verification_changes SET new_value = 'OVERWRITTEN' WHERE id = change_a;
        RAISE EXCEPTION 'Verification correction history was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    INSERT INTO document_revisions(
        organization_id, document_id, revision_number,
        previous_revision_id, status, created_by
    ) VALUES (org_a, document_a, 2, revision_a1, 'DRAFT', user_a)
    RETURNING id INTO revision_a2;
    INSERT INTO document_files(
        organization_id, document_revision_id, storage_provider, bucket_name,
        storage_path, original_file_name, mime_type, file_size_bytes,
        checksum_sha256, uploaded_by
    ) VALUES (
        org_a, revision_a2, 'SUPABASE', 'private-evidence', 'ocr/a/r2.pdf',
        'r2.pdf', 'application/pdf', 100, sha_value, user_a
    ) RETURNING id INTO file_a2;
    INSERT INTO document_extraction_jobs(
        organization_id, document_revision_id, document_file_id,
        extraction_method, idempotency_key
    ) VALUES (org_a, revision_a2, file_a2, 'MANUAL', 'ocr-org-a-r2')
    RETURNING id INTO job_a2;
    INSERT INTO document_verifications(
        organization_id, document_revision_id, extraction_job_id, status
    ) VALUES (org_a, revision_a2, job_a2, 'PENDING');

    IF NOT EXISTS (
        SELECT 1 FROM document_extraction_jobs
        WHERE id = job_a2 AND document_revision_id = revision_a2
    ) THEN
        RAISE EXCEPTION 'New revision did not receive an independent extraction cycle';
    END IF;
END $$;

ROLLBACK;

SELECT 'phase 04 OCR, lab, measurement, and verification assertions passed' AS result;
