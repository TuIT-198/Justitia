CREATE TABLE measurement_dimensions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code citext NOT NULL UNIQUE,
    name text NOT NULL,
    description text,
    canonical_unit_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (code::text = upper(code::text)),
    CHECK (length(btrim(code::text)) > 0),
    CHECK (length(btrim(name)) > 0)
);

CREATE TABLE measurement_units (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dimension_id uuid NOT NULL REFERENCES measurement_dimensions(id) ON DELETE RESTRICT,
    code citext NOT NULL UNIQUE,
    symbol text NOT NULL,
    conversion_factor numeric NOT NULL CHECK (conversion_factor > 0),
    conversion_offset numeric NOT NULL DEFAULT 0,
    is_canonical boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (dimension_id, id),
    CHECK (code::text = upper(code::text)),
    CHECK (length(btrim(code::text)) > 0),
    CHECK (length(btrim(symbol)) > 0),
    CHECK (NOT is_canonical OR (conversion_factor = 1 AND conversion_offset = 0))
);

CREATE UNIQUE INDEX uq_measurement_units_active_canonical_dimension
    ON measurement_units(dimension_id)
    WHERE is_canonical AND is_active;

ALTER TABLE measurement_dimensions
    ADD CONSTRAINT fk_measurement_dimensions_canonical_unit
    FOREIGN KEY (id, canonical_unit_id)
    REFERENCES measurement_units(dimension_id, id) ON DELETE RESTRICT;

CREATE FUNCTION validate_measurement_dimension_canonical_unit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.canonical_unit_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM measurement_units unit_record
        WHERE unit_record.id = NEW.canonical_unit_id
          AND unit_record.dimension_id = NEW.id
          AND unit_record.is_canonical
          AND unit_record.is_active
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'canonical_unit_id must reference the active canonical unit of the dimension';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_measurement_dimension_canonical_unit
BEFORE INSERT OR UPDATE OF canonical_unit_id ON measurement_dimensions
FOR EACH ROW EXECUTE FUNCTION validate_measurement_dimension_canonical_unit();

CREATE FUNCTION protect_referenced_canonical_unit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM measurement_dimensions dimension_record
        WHERE dimension_record.canonical_unit_id = OLD.id
    ) AND (
        NEW.dimension_id IS DISTINCT FROM OLD.dimension_id
        OR NOT NEW.is_canonical
        OR NOT NEW.is_active
        OR NEW.conversion_factor <> 1
        OR NEW.conversion_offset <> 0
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '55000',
            MESSAGE = 'a referenced canonical unit must remain active, canonical, and identity-converted';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_referenced_canonical_unit
BEFORE UPDATE ON measurement_units
FOR EACH ROW EXECUTE FUNCTION protect_referenced_canonical_unit();

ALTER TABLE document_files
    ADD CONSTRAINT uq_document_files_org_revision_id
    UNIQUE (organization_id, document_revision_id, id);

CREATE TABLE document_extraction_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    document_revision_id uuid NOT NULL,
    document_file_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'QUEUED'
        CHECK (status IN ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED', 'NEEDS_REVIEW', 'CANCELLED')),
    extraction_method text NOT NULL
        CHECK (extraction_method IN ('OCR', 'VISION_LLM', 'PARSER', 'MANUAL')),
    provider text,
    model_name text,
    raw_text text,
    raw_output jsonb,
    confidence_score numeric,
    idempotency_key text,
    attempt_number integer NOT NULL DEFAULT 1,
    max_attempts integer NOT NULL DEFAULT 3,
    next_retry_at timestamptz,
    last_error_code text,
    error_message text,
    started_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, document_revision_id, id),
    FOREIGN KEY (organization_id, document_revision_id)
        REFERENCES document_revisions(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, document_revision_id, document_file_id)
        REFERENCES document_files(organization_id, document_revision_id, id) ON DELETE RESTRICT,
    CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 1),
    CHECK (idempotency_key IS NULL OR length(btrim(idempotency_key)) > 0),
    CHECK (attempt_number >= 1),
    CHECK (max_attempts >= 1),
    CHECK (attempt_number <= max_attempts),
    CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE UNIQUE INDEX uq_extraction_jobs_organization_idempotency
    ON document_extraction_jobs(organization_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE extracted_fields (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    extraction_job_id uuid NOT NULL,
    field_code text NOT NULL,
    field_label text,
    raw_value text,
    normalized_value text,
    data_type text NOT NULL
        CHECK (data_type IN ('TEXT', 'NUMBER', 'DATE', 'BOOLEAN', 'CODE')),
    confidence_score numeric,
    page_number integer,
    source_text text,
    bounding_box jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, extraction_job_id)
        REFERENCES document_extraction_jobs(organization_id, id) ON DELETE CASCADE,
    CHECK (length(btrim(field_code)) > 0),
    CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 1),
    CHECK (page_number IS NULL OR page_number > 0),
    CHECK (bounding_box IS NULL OR jsonb_typeof(bounding_box) = 'object')
);

CREATE TABLE lab_test_results (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    document_revision_id uuid NOT NULL,
    extraction_job_id uuid,
    analyte_name_raw text NOT NULL,
    analyte_name_normalized text,
    result_value numeric,
    result_text text,
    result_qualifier text NOT NULL
        CHECK (result_qualifier IN (
            'EXACT', 'LESS_THAN', 'LESS_THAN_LOD', 'LESS_THAN_LOQ',
            'NOT_DETECTED', 'DETECTED_NOT_QUANTIFIED', 'TEXT_ONLY'
        )),
    unit_id uuid REFERENCES measurement_units(id) ON DELETE RESTRICT,
    normalized_value numeric,
    normalized_unit_id uuid REFERENCES measurement_units(id) ON DELETE RESTRICT,
    detection_limit numeric,
    quantification_limit numeric,
    test_method text,
    confidence_score numeric,
    page_number integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, document_revision_id)
        REFERENCES document_revisions(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, document_revision_id, extraction_job_id)
        REFERENCES document_extraction_jobs(organization_id, document_revision_id, id) ON DELETE RESTRICT,
    CHECK (length(btrim(analyte_name_raw)) > 0),
    CHECK (analyte_name_normalized IS NULL OR length(btrim(analyte_name_normalized)) > 0),
    CHECK (result_qualifier <> 'EXACT' OR result_value IS NOT NULL),
    CHECK (result_qualifier <> 'LESS_THAN' OR result_value IS NOT NULL),
    CHECK (result_qualifier <> 'LESS_THAN_LOD' OR detection_limit IS NOT NULL),
    CHECK (result_qualifier <> 'LESS_THAN_LOQ' OR quantification_limit IS NOT NULL),
    CHECK (result_qualifier <> 'TEXT_ONLY' OR result_text IS NOT NULL),
    CHECK (detection_limit IS NULL OR detection_limit >= 0),
    CHECK (quantification_limit IS NULL OR quantification_limit >= 0),
    CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 1),
    CHECK (page_number IS NULL OR page_number > 0),
    CHECK (normalized_value IS NULL OR (
        result_value IS NOT NULL AND unit_id IS NOT NULL AND normalized_unit_id IS NOT NULL
    ))
);

CREATE FUNCTION validate_lab_measurement_units()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    raw_dimension_id uuid;
    normalized_dimension_id uuid;
    normalized_is_canonical boolean;
    normalized_is_active boolean;
BEGIN
    IF NEW.normalized_unit_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.unit_id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'normalized unit requires a raw unit';
    END IF;

    SELECT dimension_id INTO raw_dimension_id
    FROM measurement_units WHERE id = NEW.unit_id;

    SELECT dimension_id, is_canonical, is_active
    INTO normalized_dimension_id, normalized_is_canonical, normalized_is_active
    FROM measurement_units WHERE id = NEW.normalized_unit_id;

    IF raw_dimension_id IS DISTINCT FROM normalized_dimension_id THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'raw and normalized units must belong to the same dimension';
    END IF;

    IF NOT normalized_is_canonical OR NOT normalized_is_active THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'normalized unit must be the active canonical unit';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_lab_measurement_units
BEFORE INSERT OR UPDATE OF unit_id, normalized_unit_id ON lab_test_results
FOR EACH ROW EXECUTE FUNCTION validate_lab_measurement_units();

CREATE TABLE document_verifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    document_revision_id uuid NOT NULL,
    extraction_job_id uuid,
    status text NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'NEEDS_REVIEW', 'VERIFIED', 'REJECTED')),
    verified_by uuid REFERENCES users(id) ON DELETE RESTRICT,
    review_notes text,
    verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, document_revision_id, id),
    FOREIGN KEY (organization_id, document_revision_id)
        REFERENCES document_revisions(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, document_revision_id, extraction_job_id)
        REFERENCES document_extraction_jobs(organization_id, document_revision_id, id) ON DELETE RESTRICT,
    CHECK ((status = 'VERIFIED') = (verified_at IS NOT NULL)),
    CHECK ((status = 'VERIFIED') = (verified_by IS NOT NULL)),
    CHECK (verified_at IS NULL OR verified_at >= created_at)
);

CREATE TABLE document_verification_changes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    verification_id uuid NOT NULL,
    target_type text NOT NULL
        CHECK (target_type IN ('EXTRACTED_FIELD', 'LAB_TEST_RESULT', 'MANUAL_FIELD')),
    target_id uuid,
    field_code text,
    old_value text,
    new_value text,
    change_reason text,
    changed_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    changed_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (organization_id, verification_id)
        REFERENCES document_verifications(organization_id, id) ON DELETE CASCADE,
    CHECK (target_type = 'MANUAL_FIELD' OR target_id IS NOT NULL),
    CHECK (field_code IS NULL OR length(btrim(field_code)) > 0),
    CHECK (old_value IS DISTINCT FROM new_value)
);

CREATE FUNCTION validate_verification_change_target()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    verification_revision_id uuid;
    target_revision_id uuid;
BEGIN
    SELECT document_revision_id INTO verification_revision_id
    FROM document_verifications
    WHERE organization_id = NEW.organization_id AND id = NEW.verification_id;

    IF NEW.target_type = 'EXTRACTED_FIELD' THEN
        SELECT job.document_revision_id INTO target_revision_id
        FROM extracted_fields field_record
        JOIN document_extraction_jobs job
          ON job.organization_id = field_record.organization_id
         AND job.id = field_record.extraction_job_id
        WHERE field_record.organization_id = NEW.organization_id
          AND field_record.id = NEW.target_id;
    ELSIF NEW.target_type = 'LAB_TEST_RESULT' THEN
        SELECT result_record.document_revision_id INTO target_revision_id
        FROM lab_test_results result_record
        WHERE result_record.organization_id = NEW.organization_id
          AND result_record.id = NEW.target_id;
    ELSE
        RETURN NEW;
    END IF;

    IF target_revision_id IS NULL OR target_revision_id <> verification_revision_id THEN
        RAISE EXCEPTION USING
            ERRCODE = '23503',
            MESSAGE = 'verification change target must belong to the same tenant and revision';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_verification_change_target
BEFORE INSERT OR UPDATE OF organization_id, verification_id, target_type, target_id
ON document_verification_changes
FOR EACH ROW EXECUTE FUNCTION validate_verification_change_target();

CREATE FUNCTION protect_verified_structured_evidence()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    old_revision_id uuid;
    new_revision_id uuid;
    revision_is_protected boolean;
BEGIN
    IF TG_TABLE_NAME = 'document_verification_changes' AND TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION USING
            ERRCODE = '55000',
            MESSAGE = 'verification correction history is append-only';
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        IF TG_TABLE_NAME = 'document_extraction_jobs' THEN
            old_revision_id := OLD.document_revision_id;
        ELSIF TG_TABLE_NAME = 'extracted_fields' THEN
            SELECT document_revision_id INTO old_revision_id
            FROM document_extraction_jobs
            WHERE organization_id = OLD.organization_id AND id = OLD.extraction_job_id;
        ELSIF TG_TABLE_NAME = 'lab_test_results' THEN
            old_revision_id := OLD.document_revision_id;
        ELSIF TG_TABLE_NAME = 'document_verifications' THEN
            old_revision_id := OLD.document_revision_id;
        ELSIF TG_TABLE_NAME = 'document_verification_changes' THEN
            SELECT document_revision_id INTO old_revision_id
            FROM document_verifications
            WHERE organization_id = OLD.organization_id AND id = OLD.verification_id;
        END IF;

        SELECT status IN ('VERIFIED', 'SUPERSEDED') INTO revision_is_protected
        FROM document_revisions
        WHERE organization_id = OLD.organization_id AND id = old_revision_id;

        IF coalesce(revision_is_protected, false) THEN
            RAISE EXCEPTION USING
                ERRCODE = '55000',
                MESSAGE = 'structured evidence of a verified or superseded revision is immutable';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF TG_TABLE_NAME = 'document_extraction_jobs' THEN
            new_revision_id := NEW.document_revision_id;
        ELSIF TG_TABLE_NAME = 'extracted_fields' THEN
            SELECT document_revision_id INTO new_revision_id
            FROM document_extraction_jobs
            WHERE organization_id = NEW.organization_id AND id = NEW.extraction_job_id;
        ELSIF TG_TABLE_NAME = 'lab_test_results' THEN
            new_revision_id := NEW.document_revision_id;
        ELSIF TG_TABLE_NAME = 'document_verifications' THEN
            new_revision_id := NEW.document_revision_id;
        ELSIF TG_TABLE_NAME = 'document_verification_changes' THEN
            SELECT document_revision_id INTO new_revision_id
            FROM document_verifications
            WHERE organization_id = NEW.organization_id AND id = NEW.verification_id;
        END IF;

        SELECT status IN ('VERIFIED', 'SUPERSEDED') INTO revision_is_protected
        FROM document_revisions
        WHERE organization_id = NEW.organization_id AND id = new_revision_id;

        IF coalesce(revision_is_protected, false) THEN
            RAISE EXCEPTION USING
                ERRCODE = '55000',
                MESSAGE = 'structured evidence cannot be added to or changed on a verified revision';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_extraction_jobs
BEFORE INSERT OR UPDATE OR DELETE ON document_extraction_jobs
FOR EACH ROW EXECUTE FUNCTION protect_verified_structured_evidence();
CREATE TRIGGER trg_protect_extracted_fields
BEFORE INSERT OR UPDATE OR DELETE ON extracted_fields
FOR EACH ROW EXECUTE FUNCTION protect_verified_structured_evidence();
CREATE TRIGGER trg_protect_lab_test_results
BEFORE INSERT OR UPDATE OR DELETE ON lab_test_results
FOR EACH ROW EXECUTE FUNCTION protect_verified_structured_evidence();
CREATE TRIGGER trg_protect_document_verifications
BEFORE INSERT OR UPDATE OR DELETE ON document_verifications
FOR EACH ROW EXECUTE FUNCTION protect_verified_structured_evidence();
CREATE TRIGGER trg_protect_document_verification_changes
BEFORE INSERT OR UPDATE OR DELETE ON document_verification_changes
FOR EACH ROW EXECUTE FUNCTION protect_verified_structured_evidence();

CREATE INDEX idx_extraction_jobs_organization_revision
    ON document_extraction_jobs(organization_id, document_revision_id);
CREATE INDEX idx_extraction_jobs_organization_status
    ON document_extraction_jobs(organization_id, status);
CREATE INDEX idx_extracted_fields_organization_job
    ON extracted_fields(organization_id, extraction_job_id);
CREATE INDEX idx_extracted_fields_organization_code
    ON extracted_fields(organization_id, field_code);
CREATE INDEX idx_lab_results_organization_revision
    ON lab_test_results(organization_id, document_revision_id);
CREATE INDEX idx_lab_results_organization_analyte
    ON lab_test_results(organization_id, analyte_name_normalized);
CREATE INDEX idx_verifications_organization_revision
    ON document_verifications(organization_id, document_revision_id);
CREATE INDEX idx_verifications_organization_status
    ON document_verifications(organization_id, status);
CREATE INDEX idx_verification_changes_organization_verification
    ON document_verification_changes(organization_id, verification_id);

