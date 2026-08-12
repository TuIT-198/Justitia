BEGIN;

DO $$
DECLARE
    vn_id uuid;
    cn_id uuid;
    market_id_value uuid;
    source_id_value uuid;
    legal_document_id uuid;
    outside_document_id uuid;
    legal_version_id uuid;
    outside_version_id uuid;
    section_id_value uuid;
    outside_section_id uuid;
    chunk_id_value uuid;
    outside_chunk_id uuid;
    citation_a uuid;
    citation_b uuid;
    outside_citation uuid;
    user_a uuid;
    user_b uuid;
    org_a uuid;
    org_b uuid;
    batch_a uuid;
    check_a uuid;
    check_b uuid;
    ai_run_id_value uuid;
    ai_finding_id uuid;
    review_finding_id uuid;
    retrieved_count integer;
    hash_a text := repeat('a', 64);
    hash_b text := repeat('b', 64);
BEGIN
    SELECT id INTO vn_id FROM countries WHERE iso2_code = 'VN';
    SELECT id INTO cn_id FROM countries WHERE iso2_code = 'CN';
    SELECT id INTO market_id_value FROM markets WHERE code = 'CN_GACC';

    INSERT INTO legal_sources(name, source_type, is_official, trust_level)
    VALUES ('TEST PHASE 07 SOURCE', 'OFFICIAL_PUBLICATION', true, 'PRIMARY')
    RETURNING id INTO source_id_value;
    INSERT INTO legal_documents(source_id, title, document_type, jurisdiction_type, language_code)
    VALUES (source_id_value, 'TEST Phase 07 snapshotted document', 'REGULATION', 'NATIONAL', 'en')
    RETURNING id INTO legal_document_id;
    INSERT INTO legal_documents(source_id, title, document_type, jurisdiction_type, language_code)
    VALUES (source_id_value, 'TEST Phase 07 outside document', 'REGULATION', 'NATIONAL', 'en')
    RETURNING id INTO outside_document_id;
    INSERT INTO legal_document_versions(legal_document_id, version_number, status, content_hash)
    VALUES (legal_document_id, 1, 'UNDER_REVIEW', hash_a)
    RETURNING id INTO legal_version_id;
    INSERT INTO legal_document_versions(legal_document_id, version_number, status, content_hash)
    VALUES (outside_document_id, 1, 'UNDER_REVIEW', hash_b)
    RETURNING id INTO outside_version_id;
    INSERT INTO legal_sections(version_id, section_type, content, order_index)
    VALUES (legal_version_id, 'ARTICLE', 'TEST snapshotted legal section content', 0)
    RETURNING id INTO section_id_value;
    INSERT INTO legal_sections(version_id, section_type, content, order_index)
    VALUES (outside_version_id, 'ARTICLE', 'TEST outside legal section content', 0)
    RETURNING id INTO outside_section_id;
    INSERT INTO legal_citations(version_id, section_id, citation_code, display_label)
    VALUES (legal_version_id, section_id_value, 'TEST-P07-A', 'TEST Phase 07 citation A')
    RETURNING id INTO citation_a;
    INSERT INTO legal_citations(version_id, section_id, citation_code, display_label)
    VALUES (legal_version_id, section_id_value, 'TEST-P07-B', 'TEST Phase 07 citation B')
    RETURNING id INTO citation_b;
    INSERT INTO legal_citations(version_id, section_id, citation_code, display_label)
    VALUES (outside_version_id, outside_section_id, 'TEST-P07-OUTSIDE', 'TEST outside citation')
    RETURNING id INTO outside_citation;
    UPDATE legal_document_versions SET status = 'APPROVED'
    WHERE id IN (legal_version_id, outside_version_id);

    INSERT INTO legal_chunks(section_id, chunk_index, content, token_count, content_hash, metadata)
    VALUES (section_id_value, 0, 'TEST snapshotted legal section content', 5, hash_a, '{"fixture":true}')
    RETURNING id INTO chunk_id_value;
    INSERT INTO legal_chunks(section_id, chunk_index, content, token_count, content_hash)
    VALUES (outside_section_id, 0, 'TEST outside legal section content', 5, hash_b)
    RETURNING id INTO outside_chunk_id;

    BEGIN
        INSERT INTO legal_chunks(section_id, chunk_index, content)
        VALUES (gen_random_uuid(), 0, 'TEST missing section');
        RAISE EXCEPTION 'Chunk without a legal section was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO legal_chunks(section_id, chunk_index, content)
        VALUES (section_id_value, 0, 'TEST snapshotted legal section content');
        RAISE EXCEPTION 'Duplicate section/chunk index was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO legal_chunks(section_id, chunk_index, content)
        VALUES (section_id_value, 1, 'content not present in section');
        RAISE EXCEPTION 'Chunk content outside its legal section was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    INSERT INTO legal_embeddings(
        chunk_id, embedding, embedding_model, embedding_dimension, content_hash
    ) VALUES (chunk_id_value, '[1,0,0]'::vector, 'fake-deterministic-v1', 3, hash_a);
    INSERT INTO legal_embeddings(
        chunk_id, embedding, embedding_model, embedding_dimension, content_hash
    ) VALUES (outside_chunk_id, '[0.9,0.1,0]'::vector, 'fake-deterministic-v1', 3, hash_b);
    BEGIN
        INSERT INTO legal_embeddings(
            chunk_id, embedding, embedding_model, embedding_dimension, content_hash
        ) VALUES (gen_random_uuid(), '[1,0,0]'::vector, 'fake-deterministic-v1', 3, hash_a);
        RAISE EXCEPTION 'Embedding without a valid chunk was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO legal_embeddings(
            chunk_id, embedding, embedding_model, embedding_dimension, content_hash
        ) VALUES (chunk_id_value, '[1,0,0]'::vector, 'fake-deterministic-v1', 3, hash_a);
        RAISE EXCEPTION 'Duplicate chunk/model embedding was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO legal_embeddings(
            chunk_id, embedding, embedding_model, embedding_dimension, content_hash
        ) VALUES (chunk_id_value, '[1,0]'::vector, 'fake-wrong-dimension', 3, hash_a);
        RAISE EXCEPTION 'Mismatched embedding dimension was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    INSERT INTO users(email, full_name, status)
    VALUES ('phase07-a@example.com', 'Phase 07 A', 'ACTIVE') RETURNING id INTO user_a;
    INSERT INTO users(email, full_name, status)
    VALUES ('phase07-b@example.com', 'Phase 07 B', 'ACTIVE') RETURNING id INTO user_b;
    INSERT INTO organizations(name, created_by)
    VALUES ('Phase 07 Org A', user_a) RETURNING id INTO org_a;
    INSERT INTO organizations(name, created_by)
    VALUES ('Phase 07 Org B', user_b) RETURNING id INTO org_b;
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id, destination_country_id, market_id, created_by
    ) VALUES (org_a, 'PHASE07-BATCH', vn_id, cn_id, market_id_value, user_a)
    RETURNING id INTO batch_a;
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number, status, started_at
    ) VALUES (org_a, batch_a, market_id_value, user_a, 1, 'PROCESSING', now())
    RETURNING id INTO check_a;
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number, status, started_at
    ) VALUES (org_a, batch_a, market_id_value, user_a, 2, 'PROCESSING', now())
    RETURNING id INTO check_b;
    INSERT INTO compliance_check_legal_versions(organization_id, check_id, legal_document_version_id)
    VALUES (org_a, check_a, legal_version_id);

    SELECT count(*) INTO retrieved_count
    FROM retrieve_legal_chunks_for_check(
        org_a, check_a, '[1,0,0]'::vector, 'fake-deterministic-v1', 10
    ) retrieval
    WHERE retrieval.legal_document_version_id = legal_version_id
      AND retrieval.chunk_id = chunk_id_value
      AND retrieval.citation_ids @> ARRAY[citation_a, citation_b];
    IF retrieved_count <> 1 THEN
        RAISE EXCEPTION 'Snapshot-filtered retrieval did not return the expected legal chunk/citations';
    END IF;
    IF EXISTS (
        SELECT 1 FROM retrieve_legal_chunks_for_check(
            org_a, check_a, '[1,0,0]'::vector, 'fake-deterministic-v1', 10
        ) WHERE legal_document_version_id = outside_version_id
    ) THEN
        RAISE EXCEPTION 'Retrieval leaked a legal version outside the check snapshot';
    END IF;

    INSERT INTO ai_runs(
        organization_id, check_id, provider, model_name, prompt_version, status,
        input_context_hash, input_snapshot, idempotency_key, attempt_number, max_attempts,
        started_at
    ) VALUES (
        org_a, check_a, 'FAKE', 'fake-analysis-v1', 'p07-test-v1', 'PROCESSING',
        hash_a, '{"fixture":true}', 'phase07-run', 1, 3, now()
    ) RETURNING id INTO ai_run_id_value;

    BEGIN
        INSERT INTO ai_runs(
            organization_id, check_id, provider, model_name, prompt_version,
            input_context_hash, attempt_number, max_attempts
        ) VALUES (org_b, check_a, 'FAKE', 'fake', 'p1', hash_a, 1, 1);
        RAISE EXCEPTION 'Cross-tenant AI run/check link was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO ai_runs(
            organization_id, check_id, provider, model_name, prompt_version,
            input_context_hash, confidence_score, attempt_number, max_attempts
        ) VALUES (org_a, check_a, 'FAKE', 'fake', 'p1', hash_a, 1.01, 1, 1);
        RAISE EXCEPTION 'Invalid AI confidence was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO ai_runs(
            organization_id, check_id, provider, model_name, prompt_version,
            input_context_hash, idempotency_key, attempt_number, max_attempts
        ) VALUES (org_a, check_a, 'FAKE', 'fake', 'p1', hash_a, 'phase07-run', 1, 1);
        RAISE EXCEPTION 'Duplicate tenant AI idempotency key was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    UPDATE ai_runs
    SET status = 'COMPLETED',
        raw_response = '{"findings":[]}',
        validated_response = '{"findings":[]}',
        confidence_score = 0.8,
        completed_at = now()
    WHERE id = ai_run_id_value;
    BEGIN
        UPDATE ai_runs SET provider = 'REWRITTEN' WHERE id = ai_run_id_value;
        RAISE EXCEPTION 'Terminal AI run was mutable';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    BEGIN
        INSERT INTO findings(
            organization_id, check_id, source_type, finding_type, title, description,
            severity, validation_status
        ) VALUES (org_a, check_a, 'AI', 'TEST', 'TEST', 'TEST', 'LOW', 'REJECTED');
        RAISE EXCEPTION 'AI finding without ai_run_id was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO findings(
            organization_id, check_id, rule_execution_id, ai_run_id, source_type,
            finding_type, title, description, severity, validation_status
        ) VALUES (
            org_a, check_a, gen_random_uuid(), ai_run_id_value, 'AI',
            'TEST', 'TEST', 'TEST', 'LOW', 'REJECTED'
        );
        RAISE EXCEPTION 'AI finding with a rule execution was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO findings(
            organization_id, check_id, rule_execution_id, ai_run_id, source_type,
            finding_type, title, description, severity, validation_status
        ) VALUES (
            org_a, check_a, gen_random_uuid(), ai_run_id_value, 'RULE_ENGINE',
            'TEST', 'TEST', 'TEST', 'LOW', 'REJECTED'
        );
        RAISE EXCEPTION 'RULE_ENGINE finding with ai_run_id was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO findings(
            organization_id, check_id, ai_run_id, source_type,
            finding_type, title, description, severity, validation_status
        ) VALUES (
            org_a, check_a, ai_run_id_value, 'MANUAL',
            'TEST', 'TEST', 'TEST', 'LOW', 'REJECTED'
        );
        RAISE EXCEPTION 'MANUAL finding with ai_run_id was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO findings(
            organization_id, check_id, ai_run_id, source_type,
            finding_type, title, description, severity, validation_status
        ) VALUES (
            org_a, check_b, ai_run_id_value, 'AI',
            'TEST', 'TEST', 'TEST', 'LOW', 'REJECTED'
        );
        RAISE EXCEPTION 'Cross-check AI finding/run link was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    INSERT INTO findings(
        organization_id, check_id, ai_run_id, source_type,
        finding_type, title, description, severity, validation_status
    ) VALUES (
        org_a, check_a, ai_run_id_value, 'AI',
        'TEST-CITED-AI', 'TEST cited AI finding', 'TEST transaction-only AI finding',
        'LOW', 'VALIDATED'
    ) RETURNING id INTO ai_finding_id;
    INSERT INTO finding_citations(finding_id, citation_id, is_primary)
    VALUES (ai_finding_id, citation_a, true), (ai_finding_id, citation_b, false);
    IF (SELECT count(*) FROM finding_citations WHERE finding_id = ai_finding_id) <> 2 THEN
        RAISE EXCEPTION 'Multiple valid AI finding citations were not preserved';
    END IF;

    BEGIN
        INSERT INTO findings(
            organization_id, check_id, ai_run_id, source_type,
            finding_type, title, description, severity, validation_status
        ) VALUES (
            org_a, check_a, ai_run_id_value, 'AI',
            'TEST-UNCITED', 'TEST uncited', 'TEST uncited AI finding', 'HIGH', 'VALIDATED'
        );
        SET CONSTRAINTS trg_validated_finding_requires_citation IMMEDIATE;
        RAISE EXCEPTION 'Validated AI finding without citation was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    SET CONSTRAINTS trg_validated_finding_requires_citation DEFERRED;

    INSERT INTO findings(
        organization_id, check_id, ai_run_id, source_type,
        finding_type, title, description, severity, validation_status
    ) VALUES (
        org_a, check_a, ai_run_id_value, 'AI',
        'TEST-REVIEW', 'TEST review', 'TEST citation review path',
        'MEDIUM', 'MANUAL_REVIEW_REQUIRED'
    ) RETURNING id INTO review_finding_id;
    BEGIN
        INSERT INTO finding_citations(finding_id, citation_id)
        VALUES (review_finding_id, gen_random_uuid());
        RAISE EXCEPTION 'Nonexistent AI citation was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO finding_citations(finding_id, citation_id)
        VALUES (review_finding_id, outside_citation);
        RAISE EXCEPTION 'Citation outside the check legal snapshot was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    IF (SELECT overall_result FROM compliance_checks WHERE id = check_a) IS NOT NULL THEN
        RAISE EXCEPTION 'AI analysis authoritatively set overall_result';
    END IF;
    IF derive_compliance_overall_result(check_a) <> 'MANUAL_REVIEW_REQUIRED' THEN
        RAISE EXCEPTION 'Unresolved AI citation did not preserve the safe manual-review result';
    END IF;
END $$;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

SELECT 'phase 07 AI RAG citation assertions passed' AS result;
