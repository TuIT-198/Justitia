BEGIN;

DO $$
DECLARE
    user_a uuid;
    user_b uuid;
    org_a uuid;
    org_b uuid;
    batch_a uuid;
    batch_b uuid;
    document_a uuid;
    document_a_replacement uuid;
    document_b uuid;
    document_org_b uuid;
    revision_a1 uuid;
    revision_a2 uuid;
    revision_b1 uuid;
    document_type_value uuid;
    vn_id uuid;
    cn_id uuid;
    market_id_value uuid;
    file_id_value uuid;
    sha_a text := repeat('a', 64);
BEGIN
    INSERT INTO users(email, full_name, status)
    VALUES ('document-a@example.com', 'Document User A', 'ACTIVE') RETURNING id INTO user_a;
    INSERT INTO users(email, full_name, status)
    VALUES ('document-b@example.com', 'Document User B', 'ACTIVE') RETURNING id INTO user_b;
    INSERT INTO organizations(name, created_by)
    VALUES ('Document Org A', user_a) RETURNING id INTO org_a;
    INSERT INTO organizations(name, created_by)
    VALUES ('Document Org B', user_b) RETURNING id INTO org_b;

    SELECT id INTO document_type_value
    FROM document_types WHERE code = 'PHYTOSANITARY_CERTIFICATE';
    SELECT id INTO vn_id FROM countries WHERE iso2_code = 'VN';
    SELECT id INTO cn_id FROM countries WHERE iso2_code = 'CN';
    SELECT id INTO market_id_value FROM markets WHERE code = 'CN_GACC';

    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id,
        destination_country_id, market_id, created_by
    ) VALUES (org_a, 'DOC-BATCH-A', vn_id, cn_id, market_id_value, user_a)
    RETURNING id INTO batch_a;
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id,
        destination_country_id, market_id, created_by
    ) VALUES (org_b, 'DOC-BATCH-B', vn_id, cn_id, market_id_value, user_b)
    RETURNING id INTO batch_b;

    INSERT INTO documents(
        organization_id, document_type_id, document_number, title,
        issue_date, expiry_date, issuing_organization, created_by
    ) VALUES (
        org_a, document_type_value, 'PHY-001', 'Phytosanitary evidence',
        DATE '2026-01-01', DATE '2026-12-31', 'Test issuer', user_a
    ) RETURNING id INTO document_a;

    INSERT INTO documents(
        organization_id, document_type_id, document_number, title, created_by
    ) VALUES (org_a, document_type_value, 'PHY-001', 'Same number is allowed', user_a)
    RETURNING id INTO document_b;

    INSERT INTO documents(
        organization_id, document_type_id, document_number, title, created_by
    ) VALUES (org_b, document_type_value, 'PHY-001', 'Other tenant document', user_b)
    RETURNING id INTO document_org_b;

    BEGIN
        INSERT INTO documents(
            organization_id, document_type_id, issue_date, expiry_date, created_by
        ) VALUES (
            org_a, document_type_value, DATE '2026-12-31', DATE '2026-01-01', user_a
        );
        RAISE EXCEPTION 'Invalid document issue/expiry range was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO documents(
        organization_id, document_type_id, document_number,
        supersedes_document_id, created_by
    ) VALUES (org_a, document_type_value, 'PHY-002', document_a, user_a)
    RETURNING id INTO document_a_replacement;

    BEGIN
        INSERT INTO documents(
            organization_id, document_type_id, document_number,
            supersedes_document_id, created_by
        ) VALUES (org_b, document_type_value, 'INVALID-REPLACEMENT', document_a, user_b);
        RAISE EXCEPTION 'Cross-tenant replacement document was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO document_revisions(
        organization_id, document_id, revision_number,
        status, content_checksum, created_by
    ) VALUES (org_a, document_a, 1, 'DRAFT', sha_a, user_a)
    RETURNING id INTO revision_a1;

    BEGIN
        INSERT INTO document_revisions(
            organization_id, document_id, revision_number, created_by
        ) VALUES (org_a, document_a, 1, user_a);
        RAISE EXCEPTION 'Duplicate revision number was accepted for one document';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO document_revisions(
        organization_id, document_id, revision_number, created_by
    ) VALUES (org_a, document_b, 1, user_a)
    RETURNING id INTO revision_b1;

    BEGIN
        INSERT INTO document_revisions(
            organization_id, document_id, revision_number,
            previous_revision_id, created_by
        ) VALUES (org_a, document_b, 2, revision_a1, user_a);
        RAISE EXCEPTION 'Previous revision from another document was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO document_revisions(
            organization_id, document_id, revision_number, created_by
        ) VALUES (org_b, document_a, 2, user_b);
        RAISE EXCEPTION 'Cross-tenant revision/document link was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO document_files(
        organization_id, document_revision_id, storage_provider,
        bucket_name, storage_path, original_file_name, mime_type,
        file_size_bytes, checksum_sha256, page_count, uploaded_by, is_original
    ) VALUES (
        org_a, revision_a1, 'SUPABASE', 'private-evidence',
        'org-a/doc-a/revision-1/evidence.pdf', 'evidence.pdf', 'application/pdf',
        2048, sha_a, 2, user_a, true
    ) RETURNING id INTO file_id_value;

    BEGIN
        INSERT INTO document_files(
            organization_id, document_revision_id, storage_provider,
            bucket_name, storage_path, original_file_name, mime_type,
            file_size_bytes, checksum_sha256, uploaded_by
        ) VALUES (
            org_b, revision_a1, 'SUPABASE', 'private-evidence',
            'invalid/cross-tenant.pdf', 'invalid.pdf', 'application/pdf',
            1, sha_a, user_b
        );
        RAISE EXCEPTION 'Cross-tenant file/revision link was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO document_files(
            organization_id, document_revision_id, storage_provider,
            bucket_name, storage_path, original_file_name, mime_type,
            file_size_bytes, checksum_sha256, page_count, uploaded_by
        ) VALUES (
            org_a, revision_b1, 'SUPABASE', 'private-evidence',
            'invalid/size.pdf', 'invalid.pdf', 'application/pdf',
            -1, sha_a, 0, user_a
        );
        RAISE EXCEPTION 'Invalid file size/page count was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM document_files
        WHERE id = file_id_value
          AND storage_path = 'org-a/doc-a/revision-1/evidence.pdf'
          AND checksum_sha256 = sha_a
          AND storage_path !~* '^https?://'
    ) THEN
        RAISE EXCEPTION 'Private file path/checksum metadata was not retained';
    END IF;

    UPDATE document_revisions
    SET status = 'VERIFIED', verified_at = clock_timestamp()
    WHERE id = revision_a1;

    BEGIN
        UPDATE document_revisions
        SET content_checksum = repeat('b', 64)
        WHERE id = revision_a1;
        RAISE EXCEPTION 'Verified revision content was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        UPDATE document_files
        SET storage_path = 'org-a/doc-a/revision-1/overwritten.pdf'
        WHERE id = file_id_value;
        RAISE EXCEPTION 'Verified revision file was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        INSERT INTO document_files(
            organization_id, document_revision_id, storage_provider,
            bucket_name, storage_path, original_file_name, mime_type,
            file_size_bytes, checksum_sha256, uploaded_by
        ) VALUES (
            org_a, revision_a1, 'SUPABASE', 'private-evidence',
            'org-a/doc-a/revision-1/late-file.pdf', 'late-file.pdf', 'application/pdf',
            1, sha_a, user_a
        );
        RAISE EXCEPTION 'File was added to a verified revision';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    BEGIN
        INSERT INTO document_files(
            organization_id, document_revision_id, storage_provider,
            bucket_name, storage_path, original_file_name, mime_type,
            file_size_bytes, checksum_sha256, uploaded_by, is_original
        ) VALUES (
            org_a, revision_b1, 'SUPABASE', 'private-evidence',
            'org-a/doc-b/revision-1/no-checksum.pdf', 'no-checksum.pdf', 'application/pdf',
            1, NULL, user_a, true
        );
        RAISE EXCEPTION 'Original file without checksum was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        DELETE FROM document_revisions WHERE id = revision_a1;
        RAISE EXCEPTION 'Verified revision was deletable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL;
    END;

    INSERT INTO document_revisions(
        organization_id, document_id, revision_number,
        previous_revision_id, status, created_by
    ) VALUES (org_a, document_a, 2, revision_a1, 'DRAFT', user_a)
    RETURNING id INTO revision_a2;

    UPDATE document_revisions
    SET status = 'SUPERSEDED', superseded_at = clock_timestamp()
    WHERE id = revision_a1;

    IF NOT EXISTS (
        SELECT 1 FROM document_revisions
        WHERE id = revision_a2 AND previous_revision_id = revision_a1
    ) THEN
        RAISE EXCEPTION 'New revision lineage was not retained';
    END IF;

    INSERT INTO batch_documents(
        organization_id, batch_id, document_id, purpose, attached_by
    ) VALUES (org_a, batch_a, document_a, 'EXPORT_EVIDENCE', user_a);

    BEGIN
        INSERT INTO batch_documents(
            organization_id, batch_id, document_id, purpose, attached_by
        ) VALUES (org_a, batch_a, document_a, 'DUPLICATE', user_a);
        RAISE EXCEPTION 'Duplicate batch/document attachment was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO batch_documents(
            organization_id, batch_id, document_id, attached_by
        ) VALUES (org_b, batch_b, document_a, user_b);
        RAISE EXCEPTION 'Cross-tenant batch/document attachment was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;
END $$;

ROLLBACK;

SELECT 'phase 03 document revision and storage assertions passed' AS result;
