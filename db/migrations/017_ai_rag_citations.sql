CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE legal_chunks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id uuid NOT NULL REFERENCES legal_sections(id) ON DELETE CASCADE,
    chunk_index integer NOT NULL CHECK (chunk_index >= 0),
    content text NOT NULL,
    token_count integer,
    content_hash text,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (section_id, chunk_index),
    CHECK (length(btrim(content)) > 0),
    CHECK (token_count IS NULL OR token_count > 0),
    CHECK (content_hash IS NULL OR content_hash ~ '^[0-9a-fA-F]{64}$'),
    CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object')
);

CREATE FUNCTION validate_legal_chunk_source()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    section_content text;
BEGIN
    SELECT content INTO section_content FROM legal_sections WHERE id = NEW.section_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'legal chunk requires an existing legal section';
    END IF;
    IF strpos(section_content, NEW.content) = 0 THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'legal chunk content must be an exact span of its legal section content';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_legal_chunk_source
BEFORE INSERT OR UPDATE OF section_id, content ON legal_chunks
FOR EACH ROW EXECUTE FUNCTION validate_legal_chunk_source();

CREATE TABLE legal_embeddings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    chunk_id uuid NOT NULL REFERENCES legal_chunks(id) ON DELETE CASCADE,
    embedding vector NOT NULL,
    embedding_model text NOT NULL,
    embedding_dimension integer NOT NULL CHECK (embedding_dimension > 0),
    content_hash text NOT NULL CHECK (content_hash ~ '^[0-9a-fA-F]{64}$'),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (chunk_id, embedding_model),
    CHECK (length(btrim(embedding_model)) > 0)
);

CREATE FUNCTION validate_legal_embedding()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    chunk_hash text;
BEGIN
    IF vector_dims(NEW.embedding) <> NEW.embedding_dimension THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'embedding dimension metadata does not match vector';
    END IF;
    IF vector_norm(NEW.embedding) = 0 THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'zero embedding cannot be used for cosine retrieval';
    END IF;

    SELECT content_hash INTO chunk_hash FROM legal_chunks WHERE id = NEW.chunk_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'legal embedding requires an existing chunk';
    END IF;
    IF chunk_hash IS NULL OR lower(chunk_hash) <> lower(NEW.content_hash) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'embedding content hash must match its chunk';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_legal_embedding
BEFORE INSERT OR UPDATE OF chunk_id, embedding, embedding_dimension, content_hash ON legal_embeddings
FOR EACH ROW EXECUTE FUNCTION validate_legal_embedding();

CREATE TABLE ai_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    check_id uuid NOT NULL,
    provider text NOT NULL,
    model_name text NOT NULL,
    prompt_version text NOT NULL,
    status text NOT NULL DEFAULT 'QUEUED'
        CHECK (status IN ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED', 'INVALID_OUTPUT', 'CANCELLED')),
    input_context_hash text NOT NULL,
    input_snapshot jsonb,
    retrieved_context jsonb NOT NULL DEFAULT '[]'::jsonb,
    raw_response jsonb,
    validated_response jsonb,
    confidence_score numeric,
    idempotency_key text,
    attempt_number integer NOT NULL DEFAULT 1,
    max_attempts integer NOT NULL DEFAULT 3,
    next_retry_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    last_error_code text,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, check_id, id),
    FOREIGN KEY (organization_id, check_id)
        REFERENCES compliance_checks(organization_id, id) ON DELETE CASCADE,
    CHECK (length(btrim(provider)) > 0),
    CHECK (length(btrim(model_name)) > 0),
    CHECK (length(btrim(prompt_version)) > 0),
    CHECK (input_context_hash ~ '^[0-9a-fA-F]{64}$'),
    CHECK (input_snapshot IS NULL OR jsonb_typeof(input_snapshot) = 'object'),
    CHECK (jsonb_typeof(retrieved_context) = 'array'),
    CHECK (validated_response IS NULL OR jsonb_typeof(validated_response) = 'object'),
    CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
    CHECK (idempotency_key IS NULL OR length(btrim(idempotency_key)) > 0),
    CHECK (attempt_number >= 1 AND max_attempts >= 1 AND attempt_number <= max_attempts),
    CHECK ((status IN ('COMPLETED', 'FAILED', 'INVALID_OUTPUT', 'CANCELLED')) = (completed_at IS NOT NULL)),
    CHECK (status <> 'COMPLETED' OR validated_response IS NOT NULL),
    CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE FUNCTION protect_ai_run_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    check_status text;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE')
       AND OLD.status IN ('COMPLETED', 'FAILED', 'INVALID_OUTPUT', 'CANCELLED') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal AI runs are immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    SELECT status INTO check_status
    FROM compliance_checks
    WHERE organization_id = NEW.organization_id AND id = NEW.check_id;
    IF check_status = 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'completed checks cannot accept AI runs';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_ai_run_lifecycle
BEFORE INSERT OR UPDATE OR DELETE ON ai_runs
FOR EACH ROW EXECUTE FUNCTION protect_ai_run_lifecycle();

CREATE UNIQUE INDEX uq_ai_runs_organization_idempotency
    ON ai_runs(organization_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

ALTER TABLE findings
    ADD COLUMN ai_run_id uuid;

ALTER TABLE findings
    DROP CONSTRAINT findings_source_type_check,
    DROP CONSTRAINT findings_check;

ALTER TABLE findings
    ADD CONSTRAINT findings_source_type_check
        CHECK (source_type IN ('RULE_ENGINE', 'MANUAL', 'AI')),
    ADD CONSTRAINT fk_findings_ai_run
        FOREIGN KEY (organization_id, check_id, ai_run_id)
        REFERENCES ai_runs(organization_id, check_id, id) ON DELETE RESTRICT,
    ADD CONSTRAINT findings_source_reference_check CHECK (
        (source_type = 'RULE_ENGINE' AND rule_execution_id IS NOT NULL AND ai_run_id IS NULL)
        OR (source_type = 'MANUAL' AND rule_execution_id IS NULL AND ai_run_id IS NULL)
        OR (source_type = 'AI' AND rule_execution_id IS NULL AND ai_run_id IS NOT NULL)
    );

CREATE FUNCTION validate_ai_finding_run()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    run_status text;
BEGIN
    IF NEW.source_type = 'AI' THEN
        SELECT status INTO run_status FROM ai_runs
        WHERE organization_id = NEW.organization_id
          AND check_id = NEW.check_id
          AND id = NEW.ai_run_id;
        IF run_status <> 'COMPLETED' THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'AI findings require a completed AI run';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_ai_finding_run
BEFORE INSERT OR UPDATE OF organization_id, check_id, source_type, ai_run_id ON findings
FOR EACH ROW EXECUTE FUNCTION validate_ai_finding_run();

CREATE FUNCTION retrieve_legal_chunks_for_check(
    target_organization_id uuid,
    target_check_id uuid,
    query_embedding vector,
    target_embedding_model text,
    top_k integer DEFAULT 10
)
RETURNS TABLE (
    chunk_id uuid,
    section_id uuid,
    legal_document_version_id uuid,
    content text,
    citation_ids uuid[],
    score double precision
)
LANGUAGE sql
STABLE
AS $$
    WITH eligible AS MATERIALIZED (
        SELECT
            chunk_record.id AS chunk_id,
            chunk_record.section_id,
            section_record.version_id,
            chunk_record.content,
            embedding_record.embedding,
            ARRAY(
                SELECT citation_record.id
                FROM legal_citations citation_record
                WHERE citation_record.version_id = section_record.version_id
                  AND citation_record.section_id = section_record.id
                ORDER BY citation_record.id
            ) AS citation_ids
        FROM compliance_checks check_record
        JOIN compliance_check_legal_versions snapshot
          ON snapshot.organization_id = check_record.organization_id
         AND snapshot.check_id = check_record.id
        JOIN legal_sections section_record
          ON section_record.version_id = snapshot.legal_document_version_id
        JOIN legal_chunks chunk_record ON chunk_record.section_id = section_record.id
        JOIN legal_embeddings embedding_record ON embedding_record.chunk_id = chunk_record.id
        WHERE check_record.organization_id = target_organization_id
          AND check_record.id = target_check_id
          AND embedding_record.embedding_model = target_embedding_model
          AND vector_dims(embedding_record.embedding) = vector_dims(query_embedding)
    ), scored AS MATERIALIZED (
        SELECT eligible.*,
               eligible.embedding <=> query_embedding AS cosine_distance
        FROM eligible
    )
    SELECT
        scored.chunk_id,
        scored.section_id,
        scored.version_id,
        scored.content,
        scored.citation_ids,
        1 - scored.cosine_distance
    FROM scored
    WHERE scored.cosine_distance IS NOT NULL
    ORDER BY scored.cosine_distance, scored.chunk_id
    LIMIT greatest(1, least(coalesce(top_k, 10), 100));
$$;

CREATE INDEX idx_legal_chunks_section ON legal_chunks(section_id);
CREATE INDEX idx_legal_embeddings_model_dimension
    ON legal_embeddings(embedding_model, embedding_dimension);
CREATE INDEX idx_ai_runs_check_created
    ON ai_runs(organization_id, check_id, created_at);
CREATE INDEX idx_ai_runs_status
    ON ai_runs(organization_id, status, created_at);
CREATE INDEX idx_findings_ai_run
    ON findings(organization_id, check_id, ai_run_id)
    WHERE ai_run_id IS NOT NULL;
