CREATE TABLE compliance_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_code citext NOT NULL UNIQUE,
    legal_requirement_id uuid NOT NULL REFERENCES legal_requirements(id) ON DELETE RESTRICT,
    rule_type text NOT NULL
        CHECK (rule_type IN (
            'NUMERIC_LIMIT', 'DATE_VALIDITY', 'DOCUMENT_REQUIRED',
            'FIELD_MATCH', 'REGISTRY_MATCH', 'BOOLEAN_CHECK', 'OTHER'
        )),
    name text NOT NULL,
    description text,
    status text NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'ACTIVE', 'INACTIVE', 'SUPERSEDED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, legal_requirement_id),
    CHECK (length(btrim(rule_code::text)) > 0),
    CHECK (length(btrim(name)) > 0)
);

CREATE TABLE compliance_rule_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id uuid NOT NULL REFERENCES compliance_rules(id) ON DELETE CASCADE,
    version_number integer NOT NULL CHECK (version_number > 0),
    legal_document_version_id uuid NOT NULL
        REFERENCES legal_document_versions(id) ON DELETE RESTRICT,
    condition_config jsonb NOT NULL,
    effective_from date,
    effective_to date,
    status text NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'UNDER_REVIEW', 'ACTIVE', 'SUPERSEDED', 'INACTIVE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (rule_id, id),
    UNIQUE (rule_id, version_number),
    CHECK (jsonb_typeof(condition_config) = 'object'),
    CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from)
);

CREATE FUNCTION validate_compliance_rule_version_provenance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    requirement_version_id uuid;
    requirement_status text;
    legal_version_status text;
BEGIN
    SELECT section_record.version_id, requirement_record.status
    INTO requirement_version_id, requirement_status
    FROM compliance_rules rule_record
    JOIN legal_requirements requirement_record
      ON requirement_record.id = rule_record.legal_requirement_id
    JOIN legal_sections section_record ON section_record.id = requirement_record.section_id
    WHERE rule_record.id = NEW.rule_id;

    IF requirement_version_id IS NULL OR requirement_version_id <> NEW.legal_document_version_id THEN
        RAISE EXCEPTION USING
            ERRCODE = '23503',
            MESSAGE = 'rule version and legal requirement must resolve to the same legal document version';
    END IF;

    IF NEW.status = 'ACTIVE' THEN
        SELECT status INTO legal_version_status
        FROM legal_document_versions WHERE id = NEW.legal_document_version_id;
        IF requirement_status NOT IN ('APPROVED', 'ACTIVE')
           OR legal_version_status NOT IN ('APPROVED', 'ACTIVE') THEN
            RAISE EXCEPTION USING
                ERRCODE = '23514',
                MESSAGE = 'active rule version requires approved/active requirement and legal version';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_compliance_rule_version_provenance
BEFORE INSERT OR UPDATE OF rule_id, legal_document_version_id, status
ON compliance_rule_versions
FOR EACH ROW EXECUTE FUNCTION validate_compliance_rule_version_provenance();

CREATE FUNCTION protect_active_compliance_rule_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND OLD.status IN ('ACTIVE', 'SUPERSEDED') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'active rule versions are immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

    IF OLD.status IN ('ACTIVE', 'SUPERSEDED') THEN
        IF (NEW.rule_id, NEW.version_number, NEW.legal_document_version_id,
            NEW.condition_config, NEW.effective_from, NEW.effective_to, NEW.created_at)
           IS DISTINCT FROM
           (OLD.rule_id, OLD.version_number, OLD.legal_document_version_id,
            OLD.condition_config, OLD.effective_from, OLD.effective_to, OLD.created_at) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'active rule executable meaning is immutable';
        END IF;
        IF NOT (
            NEW.status = OLD.status
            OR (OLD.status = 'ACTIVE' AND NEW.status = 'SUPERSEDED')
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'invalid active rule version transition';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_active_compliance_rule_version
BEFORE UPDATE OR DELETE ON compliance_rule_versions
FOR EACH ROW EXECUTE FUNCTION protect_active_compliance_rule_version();

CREATE TABLE compliance_checks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    market_id uuid NOT NULL REFERENCES markets(id) ON DELETE RESTRICT,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    parent_check_id uuid,
    check_number integer NOT NULL CHECK (check_number > 0),
    status text NOT NULL DEFAULT 'QUEUED'
        CHECK (status IN ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    overall_result text
        CHECK (overall_result IN (
            'COMPLIANT', 'ACTION_REQUIRED', 'NON_COMPLIANT', 'MANUAL_REVIEW_REQUIRED'
        )),
    idempotency_key text,
    started_at timestamptz,
    completed_at timestamptz,
    failure_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, batch_id, id),
    UNIQUE (organization_id, batch_id, check_number),
    FOREIGN KEY (organization_id, batch_id)
        REFERENCES export_batches(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, batch_id, parent_check_id)
        REFERENCES compliance_checks(organization_id, batch_id, id) ON DELETE RESTRICT,
    CHECK (parent_check_id IS NULL OR parent_check_id <> id),
    CHECK (idempotency_key IS NULL OR length(btrim(idempotency_key)) > 0),
    CHECK ((status = 'COMPLETED') = (overall_result IS NOT NULL)),
    CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE UNIQUE INDEX uq_compliance_checks_organization_idempotency
    ON compliance_checks(organization_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

ALTER TABLE document_extraction_jobs
    ADD CONSTRAINT uq_extraction_jobs_org_revision_file_id
    UNIQUE (organization_id, document_revision_id, document_file_id, id);

CREATE TABLE compliance_check_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    check_id uuid NOT NULL,
    document_id uuid NOT NULL,
    document_revision_id uuid NOT NULL,
    document_file_id uuid NOT NULL,
    extraction_job_id uuid,
    verification_id uuid NOT NULL,
    purpose text,
    document_checksum_snapshot text NOT NULL,
    file_checksum_snapshot text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (organization_id, check_id)
        REFERENCES compliance_checks(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, document_id)
        REFERENCES documents(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, document_id, document_revision_id)
        REFERENCES document_revisions(organization_id, document_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, document_revision_id, document_file_id)
        REFERENCES document_files(organization_id, document_revision_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, document_revision_id, document_file_id, extraction_job_id)
        REFERENCES document_extraction_jobs(organization_id, document_revision_id, document_file_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, document_revision_id, verification_id)
        REFERENCES document_verifications(organization_id, document_revision_id, id) ON DELETE RESTRICT,
    UNIQUE (organization_id, check_id, document_revision_id),
    CHECK (purpose IS NULL OR length(btrim(purpose)) > 0),
    CHECK (document_checksum_snapshot ~ '^[0-9a-fA-F]{64}$'),
    CHECK (file_checksum_snapshot ~ '^[0-9a-fA-F]{64}$')
);

CREATE TABLE compliance_check_legal_versions (
    organization_id uuid NOT NULL,
    check_id uuid NOT NULL,
    legal_document_version_id uuid NOT NULL
        REFERENCES legal_document_versions(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (check_id, legal_document_version_id),
    FOREIGN KEY (organization_id, check_id)
        REFERENCES compliance_checks(organization_id, id) ON DELETE CASCADE
);

CREATE FUNCTION validate_compliance_check_document_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    check_status text;
    check_batch_id uuid;
    revision_status text;
    revision_checksum text;
    file_checksum text;
    verification_status text;
    verification_job_id uuid;
BEGIN
    SELECT status, batch_id INTO check_status, check_batch_id
    FROM compliance_checks
    WHERE organization_id = NEW.organization_id AND id = NEW.check_id;

    IF check_status = 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'completed check snapshots are immutable';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM batch_documents
        WHERE organization_id = NEW.organization_id
          AND batch_id = check_batch_id
          AND document_id = NEW.document_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'snapshot document must be attached to the checked batch';
    END IF;

    SELECT status, content_checksum INTO revision_status, revision_checksum
    FROM document_revisions
    WHERE organization_id = NEW.organization_id AND id = NEW.document_revision_id;
    SELECT checksum_sha256 INTO file_checksum
    FROM document_files
    WHERE organization_id = NEW.organization_id AND id = NEW.document_file_id;
    SELECT status, extraction_job_id INTO verification_status, verification_job_id
    FROM document_verifications
    WHERE organization_id = NEW.organization_id AND id = NEW.verification_id;

    IF revision_status NOT IN ('VERIFIED', 'SUPERSEDED') OR verification_status <> 'VERIFIED' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'check snapshot requires verified revision and verification';
    END IF;
    IF verification_job_id IS DISTINCT FROM NEW.extraction_job_id THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'snapshot verification and extraction job must match';
    END IF;
    IF revision_checksum IS NULL
       OR lower(revision_checksum) <> lower(NEW.document_checksum_snapshot)
       OR file_checksum IS NULL
       OR lower(file_checksum) <> lower(NEW.file_checksum_snapshot) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'snapshot checksums must match immutable evidence';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_compliance_check_document_snapshot
BEFORE INSERT OR UPDATE ON compliance_check_documents
FOR EACH ROW EXECUTE FUNCTION validate_compliance_check_document_snapshot();

CREATE FUNCTION validate_compliance_check_legal_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    check_status text;
    legal_status text;
BEGIN
    SELECT status INTO check_status FROM compliance_checks
    WHERE organization_id = NEW.organization_id AND id = NEW.check_id;
    SELECT status INTO legal_status FROM legal_document_versions
    WHERE id = NEW.legal_document_version_id;

    IF check_status = 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'completed legal snapshots are immutable';
    END IF;
    IF legal_status NOT IN ('APPROVED', 'ACTIVE') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'production check requires approved or active legal version';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_compliance_check_legal_snapshot
BEFORE INSERT OR UPDATE ON compliance_check_legal_versions
FOR EACH ROW EXECUTE FUNCTION validate_compliance_check_legal_snapshot();

CREATE TABLE rule_executions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    check_id uuid NOT NULL,
    rule_version_id uuid NOT NULL REFERENCES compliance_rule_versions(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'RUNNING', 'COMPLETED', 'ERROR')),
    outcome text CHECK (outcome IN ('PASS', 'FAIL', 'SKIPPED', 'REVIEW_REQUIRED')),
    actual_value_numeric numeric,
    actual_value_text text,
    actual_unit_id uuid REFERENCES measurement_units(id) ON DELETE RESTRICT,
    actual_normalized_value numeric,
    actual_normalized_unit_id uuid REFERENCES measurement_units(id) ON DELETE RESTRICT,
    expected_value_numeric numeric,
    expected_value_text text,
    expected_unit_id uuid REFERENCES measurement_units(id) ON DELETE RESTRICT,
    expected_normalized_value numeric,
    expected_normalized_unit_id uuid REFERENCES measurement_units(id) ON DELETE RESTRICT,
    input_reference jsonb,
    execution_details jsonb,
    started_at timestamptz,
    completed_at timestamptz,
    error_code text,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, check_id, id),
    FOREIGN KEY (organization_id, check_id)
        REFERENCES compliance_checks(organization_id, id) ON DELETE CASCADE,
    CHECK ((status = 'COMPLETED') = (outcome IS NOT NULL)),
    CHECK (actual_normalized_value IS NULL OR (
        actual_value_numeric IS NOT NULL AND actual_unit_id IS NOT NULL
        AND actual_normalized_unit_id IS NOT NULL
    )),
    CHECK (expected_normalized_value IS NULL OR (
        expected_value_numeric IS NOT NULL AND expected_unit_id IS NOT NULL
        AND expected_normalized_unit_id IS NOT NULL
    )),
    CHECK (input_reference IS NULL OR jsonb_typeof(input_reference) = 'object'),
    CHECK (execution_details IS NULL OR jsonb_typeof(execution_details) = 'object'),
    CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE FUNCTION validate_rule_execution_context()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    check_status text;
    legal_version_id uuid;
    rule_status text;
    check_date date;
    effective_start date;
    effective_end date;
    raw_dimension uuid;
    normalized_dimension uuid;
    normalized_canonical boolean;
    normalized_active boolean;
BEGIN
    SELECT status, created_at::date INTO check_status, check_date
    FROM compliance_checks WHERE organization_id = NEW.organization_id AND id = NEW.check_id;
    SELECT legal_document_version_id, status, effective_from, effective_to
    INTO legal_version_id, rule_status, effective_start, effective_end
    FROM compliance_rule_versions WHERE id = NEW.rule_version_id;

    IF check_status = 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'completed check executions are immutable';
    END IF;
    IF rule_status <> 'ACTIVE'
       OR (effective_start IS NOT NULL AND check_date < effective_start)
       OR (effective_end IS NOT NULL AND check_date > effective_end) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'rule version is not active/effective for the check';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM compliance_check_legal_versions
        WHERE check_id = NEW.check_id AND legal_document_version_id = legal_version_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'rule legal version is not snapshotted by the check';
    END IF;

    IF NEW.actual_normalized_unit_id IS NOT NULL THEN
        SELECT dimension_id INTO raw_dimension FROM measurement_units WHERE id = NEW.actual_unit_id;
        SELECT dimension_id, is_canonical, is_active
        INTO normalized_dimension, normalized_canonical, normalized_active
        FROM measurement_units WHERE id = NEW.actual_normalized_unit_id;
        IF raw_dimension IS DISTINCT FROM normalized_dimension OR NOT normalized_canonical OR NOT normalized_active THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'actual normalized unit must be compatible and canonical';
        END IF;
    END IF;
    IF NEW.expected_normalized_unit_id IS NOT NULL THEN
        SELECT dimension_id INTO raw_dimension FROM measurement_units WHERE id = NEW.expected_unit_id;
        SELECT dimension_id, is_canonical, is_active
        INTO normalized_dimension, normalized_canonical, normalized_active
        FROM measurement_units WHERE id = NEW.expected_normalized_unit_id;
        IF raw_dimension IS DISTINCT FROM normalized_dimension OR NOT normalized_canonical OR NOT normalized_active THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'expected normalized unit must be compatible and canonical';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_rule_execution_context
BEFORE INSERT OR UPDATE ON rule_executions
FOR EACH ROW EXECUTE FUNCTION validate_rule_execution_context();

CREATE TABLE findings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    check_id uuid NOT NULL,
    rule_execution_id uuid,
    source_type text NOT NULL CHECK (source_type IN ('RULE_ENGINE', 'MANUAL')),
    finding_type text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    severity text NOT NULL CHECK (severity IN ('INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    validation_status text NOT NULL
        CHECK (validation_status IN ('VALIDATED', 'MANUAL_REVIEW_REQUIRED', 'REJECTED')),
    actual_value text,
    expected_value text,
    unit_text text,
    remediation_hint text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, check_id, id),
    FOREIGN KEY (organization_id, check_id)
        REFERENCES compliance_checks(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, check_id, rule_execution_id)
        REFERENCES rule_executions(organization_id, check_id, id) ON DELETE RESTRICT,
    CHECK (length(btrim(finding_type)) > 0),
    CHECK (length(btrim(title)) > 0),
    CHECK (length(btrim(description)) > 0),
    CHECK (
        (source_type = 'RULE_ENGINE' AND rule_execution_id IS NOT NULL)
        OR (source_type = 'MANUAL' AND rule_execution_id IS NULL)
    )
);

CREATE TABLE finding_citations (
    finding_id uuid NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
    citation_id uuid NOT NULL REFERENCES legal_citations(id) ON DELETE RESTRICT,
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (finding_id, citation_id)
);

CREATE FUNCTION validate_finding_citation_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    finding_check_id uuid;
    citation_version_id uuid;
    check_status text;
BEGIN
    SELECT finding_record.check_id, check_record.status
    INTO finding_check_id, check_status
    FROM findings finding_record
    JOIN compliance_checks check_record ON check_record.id = finding_record.check_id
    WHERE finding_record.id = NEW.finding_id;
    SELECT version_id INTO citation_version_id FROM legal_citations WHERE id = NEW.citation_id;

    IF check_status = 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'completed finding citations are immutable';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM compliance_check_legal_versions
        WHERE check_id = finding_check_id
          AND legal_document_version_id = citation_version_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'finding citation legal version is not in the check snapshot';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_finding_citation_snapshot
BEFORE INSERT OR UPDATE ON finding_citations
FOR EACH ROW EXECUTE FUNCTION validate_finding_citation_snapshot();

CREATE FUNCTION enforce_validated_finding_has_citation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_finding_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'findings' THEN
        target_finding_id := COALESCE(NEW.id, OLD.id);
    ELSE
        target_finding_id := COALESCE(NEW.finding_id, OLD.finding_id);
    END IF;

    IF EXISTS (
        SELECT 1 FROM findings
        WHERE id = target_finding_id AND validation_status = 'VALIDATED'
    ) AND NOT EXISTS (
        SELECT 1 FROM finding_citations WHERE finding_id = target_finding_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'validated legal finding requires at least one citation';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_validated_finding_requires_citation
AFTER INSERT OR UPDATE OF validation_status ON findings
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_validated_finding_has_citation();
CREATE CONSTRAINT TRIGGER trg_finding_citation_preserves_validation
AFTER UPDATE OR DELETE ON finding_citations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_validated_finding_has_citation();

CREATE TABLE compliance_check_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    check_id uuid NOT NULL,
    event_type text NOT NULL,
    from_status text,
    to_status text,
    actor_type text NOT NULL CHECK (actor_type IN ('USER', 'SYSTEM', 'RULE_ENGINE')),
    actor_user_id uuid REFERENCES users(id) ON DELETE RESTRICT,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (organization_id, check_id)
        REFERENCES compliance_checks(organization_id, id) ON DELETE CASCADE,
    CHECK (length(btrim(event_type)) > 0),
    CHECK ((actor_type = 'USER') = (actor_user_id IS NOT NULL)),
    CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object')
);

CREATE FUNCTION protect_append_only_compliance_events()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'compliance check events are append-only';
END;
$$;

CREATE TRIGGER trg_protect_append_only_compliance_events
BEFORE UPDATE OR DELETE ON compliance_check_events
FOR EACH ROW EXECUTE FUNCTION protect_append_only_compliance_events();

CREATE FUNCTION derive_compliance_overall_result(target_check_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM rule_executions
        WHERE check_id = target_check_id
          AND (status = 'ERROR' OR outcome = 'REVIEW_REQUIRED')
    ) OR EXISTS (
        SELECT 1 FROM findings
        WHERE check_id = target_check_id
          AND validation_status = 'MANUAL_REVIEW_REQUIRED'
    ) THEN
        RETURN 'MANUAL_REVIEW_REQUIRED';
    END IF;

    IF EXISTS (
        SELECT 1 FROM findings
        WHERE check_id = target_check_id
          AND validation_status = 'VALIDATED'
          AND severity IN ('HIGH', 'CRITICAL')
    ) THEN
        RETURN 'NON_COMPLIANT';
    END IF;

    IF EXISTS (
        SELECT 1 FROM rule_executions
        WHERE check_id = target_check_id AND outcome = 'FAIL'
    ) OR EXISTS (
        SELECT 1 FROM findings
        WHERE check_id = target_check_id
          AND validation_status = 'VALIDATED'
          AND severity IN ('LOW', 'MEDIUM')
    ) THEN
        RETURN 'ACTION_REQUIRED';
    END IF;

    IF EXISTS (SELECT 1 FROM rule_executions WHERE check_id = target_check_id)
       AND NOT EXISTS (
           SELECT 1 FROM rule_executions
           WHERE check_id = target_check_id
             AND (status <> 'COMPLETED' OR outcome NOT IN ('PASS', 'SKIPPED'))
       ) THEN
        RETURN 'COMPLIANT';
    END IF;

    RETURN 'MANUAL_REVIEW_REQUIRED';
END;
$$;

CREATE FUNCTION validate_compliance_check_completion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    derived_result text;
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'create check before completing it';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'completed compliance checks are immutable; create a re-check';
    END IF;
    IF NEW.status = 'COMPLETED' THEN
        IF NOT EXISTS (SELECT 1 FROM compliance_check_documents WHERE check_id = NEW.id)
           OR NOT EXISTS (SELECT 1 FROM compliance_check_legal_versions WHERE check_id = NEW.id)
           OR NOT EXISTS (SELECT 1 FROM rule_executions WHERE check_id = NEW.id) THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'completed check requires evidence, legal snapshot, and executions';
        END IF;
        derived_result := derive_compliance_overall_result(NEW.id);
        IF NEW.overall_result IS DISTINCT FROM derived_result THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'overall_result does not match deterministic aggregation';
        END IF;
        IF NEW.completed_at IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'completed check requires completed_at';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_compliance_check_completion
BEFORE INSERT OR UPDATE ON compliance_checks
FOR EACH ROW EXECUTE FUNCTION validate_compliance_check_completion();

CREATE FUNCTION protect_completed_check_children()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_check_id uuid;
    check_status text;
BEGIN
    IF TG_TABLE_NAME = 'finding_citations' THEN
        SELECT check_id INTO target_check_id FROM findings
        WHERE id = CASE WHEN TG_OP = 'INSERT' THEN NEW.finding_id ELSE OLD.finding_id END;
    ELSE
        target_check_id := CASE WHEN TG_OP = 'INSERT' THEN NEW.check_id ELSE OLD.check_id END;
    END IF;

    SELECT status INTO check_status FROM compliance_checks WHERE id = target_check_id;
    IF check_status = 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'completed check history is immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_completed_check_documents
BEFORE INSERT OR UPDATE OR DELETE ON compliance_check_documents
FOR EACH ROW EXECUTE FUNCTION protect_completed_check_children();
CREATE TRIGGER trg_protect_completed_check_legal_versions
BEFORE INSERT OR UPDATE OR DELETE ON compliance_check_legal_versions
FOR EACH ROW EXECUTE FUNCTION protect_completed_check_children();
CREATE TRIGGER trg_protect_completed_rule_executions
BEFORE INSERT OR UPDATE OR DELETE ON rule_executions
FOR EACH ROW EXECUTE FUNCTION protect_completed_check_children();
CREATE TRIGGER trg_protect_completed_findings
BEFORE INSERT OR UPDATE OR DELETE ON findings
FOR EACH ROW EXECUTE FUNCTION protect_completed_check_children();
CREATE TRIGGER trg_protect_completed_finding_citations
BEFORE INSERT OR UPDATE OR DELETE ON finding_citations
FOR EACH ROW EXECUTE FUNCTION protect_completed_check_children();

CREATE INDEX idx_compliance_checks_batch_created
    ON compliance_checks(organization_id, batch_id, created_at);
CREATE INDEX idx_compliance_checks_organization_status
    ON compliance_checks(organization_id, status);
CREATE INDEX idx_compliance_checks_organization_result
    ON compliance_checks(organization_id, overall_result);
CREATE INDEX idx_rule_versions_status_effective
    ON compliance_rule_versions(status, effective_from, effective_to);
CREATE INDEX idx_rule_executions_rule_version
    ON rule_executions(rule_version_id);
CREATE INDEX idx_rule_executions_outcome
    ON rule_executions(outcome);
CREATE INDEX idx_findings_severity_validation
    ON findings(severity, validation_status);
CREATE INDEX idx_check_events_organization_check_created
    ON compliance_check_events(organization_id, check_id, created_at);
