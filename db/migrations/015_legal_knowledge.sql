CREATE TABLE legal_sources (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    source_type text NOT NULL
        CHECK (source_type IN (
            'GOVERNMENT_PORTAL', 'OFFICIAL_DATABASE', 'AUTHORITY_WEBSITE',
            'TREATY_SOURCE', 'OFFICIAL_PUBLICATION', 'OTHER'
        )),
    base_url text,
    country_id uuid REFERENCES countries(id) ON DELETE RESTRICT,
    is_official boolean NOT NULL,
    trust_level text NOT NULL DEFAULT 'UNKNOWN'
        CHECK (trust_level IN ('PRIMARY', 'SECONDARY', 'UNKNOWN')),
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'UNDER_REVIEW')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (length(btrim(name)) > 0),
    CHECK (base_url IS NULL OR base_url ~* '^https://')
);

CREATE TABLE legal_authorities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    country_id uuid REFERENCES countries(id) ON DELETE RESTRICT,
    code citext UNIQUE,
    name text NOT NULL,
    short_name text,
    authority_type text,
    official_url text,
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (code IS NULL OR length(btrim(code::text)) > 0),
    CHECK (length(btrim(name)) > 0),
    CHECK (official_url IS NULL OR official_url ~* '^https://')
);

CREATE TABLE legal_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id uuid NOT NULL REFERENCES legal_sources(id) ON DELETE RESTRICT,
    document_code text,
    title text NOT NULL,
    short_title text,
    document_type text NOT NULL
        CHECK (document_type IN (
            'LAW', 'DECREE', 'CIRCULAR', 'DECISION', 'PROTOCOL',
            'REGULATION', 'STANDARD', 'NOTICE', 'GUIDELINE', 'OTHER'
        )),
    jurisdiction_type text NOT NULL
        CHECK (jurisdiction_type IN ('NATIONAL', 'BILATERAL', 'REGIONAL', 'INTERNATIONAL')),
    language_code text NOT NULL,
    signed_date date,
    publication_date date,
    current_status text NOT NULL DEFAULT 'DRAFT'
        CHECK (current_status IN ('DRAFT', 'ACTIVE', 'SUPERSEDED', 'REPEALED', 'ARCHIVED')),
    summary text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (document_code IS NULL OR length(btrim(document_code)) > 0),
    CHECK (length(btrim(title)) > 0),
    CHECK (language_code ~ '^[a-z]{2}(-[A-Z]{2})?$')
);

CREATE TABLE legal_document_parties (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    legal_document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    authority_id uuid NOT NULL REFERENCES legal_authorities(id) ON DELETE RESTRICT,
    party_role text NOT NULL
        CHECK (party_role IN (
            'SIGNATORY', 'ISSUING_AUTHORITY', 'IMPLEMENTING_AUTHORITY',
            'SUPERVISORY_AUTHORITY', 'OTHER'
        )),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (legal_document_id, authority_id, party_role)
);

CREATE TABLE legal_document_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    legal_document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
    version_number integer NOT NULL CHECK (version_number > 0),
    version_label text,
    effective_from date,
    effective_to date,
    published_at date,
    status text NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN (
            'DRAFT', 'UNDER_REVIEW', 'APPROVED', 'UPCOMING',
            'ACTIVE', 'SUPERSEDED', 'EXPIRED', 'REPEALED'
        )),
    previous_version_id uuid,
    change_summary text,
    content_hash text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (legal_document_id, id),
    UNIQUE (legal_document_id, version_number),
    FOREIGN KEY (legal_document_id, previous_version_id)
        REFERENCES legal_document_versions(legal_document_id, id) ON DELETE RESTRICT,
    CHECK (previous_version_id IS NULL OR previous_version_id <> id),
    CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from),
    CHECK (content_hash IS NULL OR content_hash ~ '^[0-9a-fA-F]{64}$')
);

CREATE TABLE legal_document_files (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_id uuid NOT NULL REFERENCES legal_document_versions(id) ON DELETE CASCADE,
    file_name text NOT NULL,
    mime_type text NOT NULL,
    storage_provider text,
    bucket_name text,
    storage_path text NOT NULL,
    language_code text NOT NULL,
    checksum_sha256 text NOT NULL,
    is_original boolean NOT NULL DEFAULT true,
    page_count integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (length(btrim(file_name)) > 0),
    CHECK (length(btrim(mime_type)) > 0),
    CHECK (length(btrim(storage_path)) > 0),
    CHECK (storage_path !~* '^https?://'),
    CHECK (language_code ~ '^[a-z]{2}(-[A-Z]{2})?$'),
    CHECK (checksum_sha256 ~ '^[0-9a-fA-F]{64}$'),
    CHECK (page_count IS NULL OR page_count > 0)
);

CREATE TABLE legal_sections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_id uuid NOT NULL REFERENCES legal_document_versions(id) ON DELETE CASCADE,
    parent_id uuid,
    section_type text NOT NULL
        CHECK (section_type IN ('PART', 'CHAPTER', 'SECTION', 'ARTICLE', 'CLAUSE', 'POINT', 'ANNEX', 'OTHER')),
    section_number text,
    title text,
    content text NOT NULL,
    order_index integer NOT NULL CHECK (order_index >= 0),
    page_start integer,
    page_end integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (version_id, id),
    FOREIGN KEY (version_id, parent_id)
        REFERENCES legal_sections(version_id, id) ON DELETE RESTRICT,
    CHECK (parent_id IS NULL OR parent_id <> id),
    CHECK (length(btrim(content)) > 0),
    CHECK (page_start IS NULL OR page_start > 0),
    CHECK (page_end IS NULL OR page_end > 0),
    CHECK (page_end IS NULL OR page_start IS NULL OR page_end >= page_start)
);

CREATE TABLE legal_requirements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id uuid NOT NULL REFERENCES legal_sections(id) ON DELETE CASCADE,
    requirement_code citext NOT NULL UNIQUE,
    title text NOT NULL,
    requirement_text text NOT NULL,
    requirement_type text NOT NULL
        CHECK (requirement_type IN (
            'FOOD_SAFETY', 'PHYTOSANITARY', 'PESTICIDE_RESIDUE', 'HEAVY_METAL',
            'TEMPERATURE', 'PACKAGING', 'LABELING', 'REGISTRATION', 'GROWING_AREA',
            'PACKING_FACILITY', 'TRACEABILITY', 'CERTIFICATE', 'IMPORT_INSPECTION',
            'STORAGE', 'TRANSPORT', 'OTHER'
        )),
    obligation_level text NOT NULL
        CHECK (obligation_level IN ('MUST', 'MUST_NOT', 'SHOULD', 'MAY', 'INFORMATIONAL')),
    validation_type text NOT NULL
        CHECK (validation_type IN (
            'BOOLEAN', 'NUMERIC_LIMIT', 'DATE_VALIDITY', 'REFERENCE_MATCH',
            'DOCUMENT_REQUIRED', 'REGISTRY_LOOKUP', 'MANUAL_REVIEW', 'OTHER'
        )),
    severity_default text NOT NULL
        CHECK (severity_default IN ('INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    priority integer NOT NULL DEFAULT 0,
    effective_from date,
    effective_to date,
    status text NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'UNDER_REVIEW', 'APPROVED', 'ACTIVE', 'SUPERSEDED', 'INACTIVE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (section_id, id),
    CHECK (length(btrim(requirement_code::text)) > 0),
    CHECK (length(btrim(title)) > 0),
    CHECK (length(btrim(requirement_text)) > 0),
    CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from)
);

CREATE TABLE requirement_scopes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id uuid NOT NULL REFERENCES legal_requirements(id) ON DELETE CASCADE,
    product_id uuid REFERENCES products(id) ON DELETE RESTRICT,
    product_form_id uuid REFERENCES product_forms(id) ON DELETE RESTRICT,
    hs_code_id uuid REFERENCES hs_codes(id) ON DELETE RESTRICT,
    origin_country_id uuid REFERENCES countries(id) ON DELETE RESTRICT,
    destination_country_id uuid REFERENCES countries(id) ON DELETE RESTRICT,
    market_id uuid REFERENCES markets(id) ON DELETE RESTRICT,
    priority integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (product_id, product_form_id)
        REFERENCES product_forms(product_id, id) ON DELETE RESTRICT
);

CREATE TABLE requirement_parameters (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id uuid NOT NULL REFERENCES legal_requirements(id) ON DELETE CASCADE,
    parameter_code text NOT NULL,
    operator text NOT NULL
        CHECK (operator IN ('EQ', 'NE', 'LT', 'LTE', 'GT', 'GTE', 'BETWEEN', 'IN', 'NOT_IN', 'EXISTS', 'NOT_EXISTS')),
    value_numeric numeric,
    value_text text,
    value_boolean boolean,
    min_value numeric,
    max_value numeric,
    unit_id uuid REFERENCES measurement_units(id) ON DELETE RESTRICT,
    normalized_value_numeric numeric,
    normalized_unit_id uuid REFERENCES measurement_units(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (requirement_id, parameter_code),
    CHECK (length(btrim(parameter_code)) > 0),
    CHECK (min_value IS NULL OR max_value IS NULL OR max_value >= min_value),
    CHECK (operator <> 'BETWEEN' OR (min_value IS NOT NULL AND max_value IS NOT NULL)),
    CHECK (normalized_value_numeric IS NULL OR (
        value_numeric IS NOT NULL AND unit_id IS NOT NULL AND normalized_unit_id IS NOT NULL
    ))
);

CREATE TABLE regulated_substances (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code citext NOT NULL UNIQUE,
    name citext NOT NULL UNIQUE,
    substance_type text NOT NULL
        CHECK (substance_type IN ('PESTICIDE', 'HEAVY_METAL', 'CONTAMINANT', 'MICROBIOLOGICAL', 'OTHER')),
    cas_number text,
    aliases jsonb,
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'INACTIVE', 'UNDER_REVIEW')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (length(btrim(code::text)) > 0),
    CHECK (length(btrim(name::text)) > 0),
    CHECK (aliases IS NULL OR jsonb_typeof(aliases) = 'array')
);

ALTER TABLE lab_test_results
    ADD COLUMN regulated_substance_id uuid
        REFERENCES regulated_substances(id) ON DELETE RESTRICT;

CREATE TABLE legal_limits (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id uuid NOT NULL REFERENCES legal_requirements(id) ON DELETE CASCADE,
    substance_id uuid REFERENCES regulated_substances(id) ON DELETE RESTRICT,
    product_id uuid REFERENCES products(id) ON DELETE RESTRICT,
    product_form_id uuid REFERENCES product_forms(id) ON DELETE RESTRICT,
    hs_code_id uuid REFERENCES hs_codes(id) ON DELETE RESTRICT,
    market_id uuid REFERENCES markets(id) ON DELETE RESTRICT,
    limit_type text NOT NULL
        CHECK (limit_type IN ('MRL', 'MAX_CONTAMINANT', 'MINIMUM', 'MAXIMUM', 'RANGE', 'OTHER')),
    operator text NOT NULL CHECK (operator IN ('LT', 'LTE', 'GT', 'GTE', 'EQ')),
    limit_value numeric NOT NULL CHECK (limit_value >= 0),
    unit_id uuid NOT NULL REFERENCES measurement_units(id) ON DELETE RESTRICT,
    normalized_limit_value numeric NOT NULL CHECK (normalized_limit_value >= 0),
    normalized_unit_id uuid NOT NULL REFERENCES measurement_units(id) ON DELETE RESTRICT,
    priority integer NOT NULL DEFAULT 0,
    effective_from date NOT NULL,
    effective_to date,
    status text NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'UNDER_REVIEW', 'APPROVED', 'ACTIVE', 'SUPERSEDED', 'INACTIVE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (product_id, product_form_id)
        REFERENCES product_forms(product_id, id) ON DELETE RESTRICT,
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE FUNCTION validate_legal_normalized_units()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    raw_unit_id uuid;
    canonical_unit_id uuid;
    raw_dimension_id uuid;
    normalized_dimension_id uuid;
    normalized_is_canonical boolean;
    normalized_is_active boolean;
BEGIN
    raw_unit_id := NEW.unit_id;
    canonical_unit_id := NEW.normalized_unit_id;

    IF canonical_unit_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF raw_unit_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'normalized unit requires a raw unit';
    END IF;

    SELECT dimension_id INTO raw_dimension_id
    FROM measurement_units WHERE id = raw_unit_id;
    SELECT dimension_id, is_canonical, is_active
    INTO normalized_dimension_id, normalized_is_canonical, normalized_is_active
    FROM measurement_units WHERE id = canonical_unit_id;

    IF raw_dimension_id IS DISTINCT FROM normalized_dimension_id THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'legal raw and normalized units must share a dimension';
    END IF;
    IF NOT normalized_is_canonical OR NOT normalized_is_active THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'legal normalized unit must be active and canonical';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_requirement_parameter_units
BEFORE INSERT OR UPDATE OF unit_id, normalized_unit_id ON requirement_parameters
FOR EACH ROW EXECUTE FUNCTION validate_legal_normalized_units();
CREATE TRIGGER trg_validate_legal_limit_units
BEFORE INSERT OR UPDATE OF unit_id, normalized_unit_id ON legal_limits
FOR EACH ROW EXECUTE FUNCTION validate_legal_normalized_units();

CREATE TABLE legal_citations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    version_id uuid NOT NULL,
    section_id uuid NOT NULL,
    requirement_id uuid,
    citation_code text NOT NULL,
    display_label text NOT NULL,
    quote_excerpt text,
    canonical_reference text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (version_id, section_id)
        REFERENCES legal_sections(version_id, id) ON DELETE CASCADE,
    FOREIGN KEY (section_id, requirement_id)
        REFERENCES legal_requirements(section_id, id) ON DELETE RESTRICT,
    UNIQUE (version_id, id),
    UNIQUE (version_id, citation_code),
    CHECK (length(btrim(citation_code)) > 0),
    CHECK (length(btrim(display_label)) > 0)
);

CREATE TABLE market_entity_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    registered_entity_id uuid NOT NULL
        REFERENCES registered_export_entities(id) ON DELETE RESTRICT,
    market_id uuid NOT NULL REFERENCES markets(id) ON DELETE RESTRICT,
    authority_id uuid NOT NULL REFERENCES legal_authorities(id) ON DELETE RESTRICT,
    source_version_id uuid NOT NULL REFERENCES legal_document_versions(id) ON DELETE RESTRICT,
    legal_citation_id uuid NOT NULL,
    approval_status text NOT NULL
        CHECK (approval_status IN ('APPROVED', 'SUSPENDED', 'REVOKED', 'EXPIRED', 'PENDING')),
    valid_from date NOT NULL,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (source_version_id, legal_citation_id)
        REFERENCES legal_citations(version_id, id) ON DELETE RESTRICT,
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE FUNCTION protect_approved_legal_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND OLD.status IN ('APPROVED', 'ACTIVE', 'SUPERSEDED', 'EXPIRED', 'REPEALED') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'approved legal versions are immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF OLD.status IN ('APPROVED', 'ACTIVE', 'SUPERSEDED', 'EXPIRED', 'REPEALED') THEN
        IF (NEW.legal_document_id, NEW.version_number, NEW.version_label,
            NEW.effective_from, NEW.effective_to, NEW.published_at,
            NEW.previous_version_id, NEW.change_summary, NEW.content_hash, NEW.created_at)
           IS DISTINCT FROM
           (OLD.legal_document_id, OLD.version_number, OLD.version_label,
            OLD.effective_from, OLD.effective_to, OLD.published_at,
            OLD.previous_version_id, OLD.change_summary, OLD.content_hash, OLD.created_at) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'approved legal version provenance is immutable';
        END IF;

        IF NOT (
            NEW.status = OLD.status
            OR (OLD.status = 'APPROVED' AND NEW.status = 'ACTIVE')
            OR (OLD.status = 'ACTIVE' AND NEW.status IN ('SUPERSEDED', 'EXPIRED', 'REPEALED'))
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'invalid approved legal version lifecycle transition';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_approved_legal_version
BEFORE UPDATE OR DELETE ON legal_document_versions
FOR EACH ROW EXECUTE FUNCTION protect_approved_legal_version();

CREATE FUNCTION protect_approved_legal_children()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    old_version_id uuid;
    new_version_id uuid;
    is_protected boolean;
BEGIN
    IF TG_TABLE_NAME = 'legal_document_files' THEN
        IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.is_original THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'original legal source files are append-only';
        END IF;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        IF TG_TABLE_NAME = 'legal_document_files' THEN
            old_version_id := OLD.version_id;
        ELSIF TG_TABLE_NAME = 'legal_sections' THEN
            old_version_id := OLD.version_id;
        ELSIF TG_TABLE_NAME = 'legal_requirements' THEN
            SELECT section_record.version_id INTO old_version_id
            FROM legal_sections section_record WHERE section_record.id = OLD.section_id;
        ELSIF TG_TABLE_NAME IN ('requirement_scopes', 'requirement_parameters', 'legal_limits') THEN
            SELECT section_record.version_id INTO old_version_id
            FROM legal_requirements requirement_record
            JOIN legal_sections section_record ON section_record.id = requirement_record.section_id
            WHERE requirement_record.id = OLD.requirement_id;
        ELSIF TG_TABLE_NAME = 'legal_citations' THEN
            old_version_id := OLD.version_id;
        END IF;

        SELECT status IN ('APPROVED', 'ACTIVE', 'SUPERSEDED', 'EXPIRED', 'REPEALED')
        INTO is_protected FROM legal_document_versions WHERE id = old_version_id;
        IF coalesce(is_protected, false) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'structured data of an approved legal version is immutable';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF TG_TABLE_NAME = 'legal_document_files' THEN
            new_version_id := NEW.version_id;
        ELSIF TG_TABLE_NAME = 'legal_sections' THEN
            new_version_id := NEW.version_id;
        ELSIF TG_TABLE_NAME = 'legal_requirements' THEN
            SELECT section_record.version_id INTO new_version_id
            FROM legal_sections section_record WHERE section_record.id = NEW.section_id;
        ELSIF TG_TABLE_NAME IN ('requirement_scopes', 'requirement_parameters', 'legal_limits') THEN
            SELECT section_record.version_id INTO new_version_id
            FROM legal_requirements requirement_record
            JOIN legal_sections section_record ON section_record.id = requirement_record.section_id
            WHERE requirement_record.id = NEW.requirement_id;
        ELSIF TG_TABLE_NAME = 'legal_citations' THEN
            new_version_id := NEW.version_id;
        END IF;

        SELECT status IN ('APPROVED', 'ACTIVE', 'SUPERSEDED', 'EXPIRED', 'REPEALED')
        INTO is_protected FROM legal_document_versions WHERE id = new_version_id;
        IF coalesce(is_protected, false) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'structured data cannot be added to an approved legal version';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_legal_document_files
BEFORE INSERT OR UPDATE OR DELETE ON legal_document_files
FOR EACH ROW EXECUTE FUNCTION protect_approved_legal_children();
CREATE TRIGGER trg_protect_legal_sections
BEFORE INSERT OR UPDATE OR DELETE ON legal_sections
FOR EACH ROW EXECUTE FUNCTION protect_approved_legal_children();
CREATE TRIGGER trg_protect_legal_requirements
BEFORE INSERT OR UPDATE OR DELETE ON legal_requirements
FOR EACH ROW EXECUTE FUNCTION protect_approved_legal_children();
CREATE TRIGGER trg_protect_requirement_scopes
BEFORE INSERT OR UPDATE OR DELETE ON requirement_scopes
FOR EACH ROW EXECUTE FUNCTION protect_approved_legal_children();
CREATE TRIGGER trg_protect_requirement_parameters
BEFORE INSERT OR UPDATE OR DELETE ON requirement_parameters
FOR EACH ROW EXECUTE FUNCTION protect_approved_legal_children();
CREATE TRIGGER trg_protect_legal_limits
BEFORE INSERT OR UPDATE OR DELETE ON legal_limits
FOR EACH ROW EXECUTE FUNCTION protect_approved_legal_children();
CREATE TRIGGER trg_protect_legal_citations
BEFORE INSERT OR UPDATE OR DELETE ON legal_citations
FOR EACH ROW EXECUTE FUNCTION protect_approved_legal_children();

CREATE INDEX idx_legal_documents_source_type
    ON legal_documents(source_id, document_type);
CREATE INDEX idx_legal_versions_document_status
    ON legal_document_versions(legal_document_id, status);
CREATE INDEX idx_legal_versions_effective_dates
    ON legal_document_versions(effective_from, effective_to);
CREATE INDEX idx_legal_sections_version_order
    ON legal_sections(version_id, order_index);
CREATE INDEX idx_legal_sections_version_parent
    ON legal_sections(version_id, parent_id);
CREATE INDEX idx_legal_requirements_section_status
    ON legal_requirements(section_id, status);
CREATE INDEX idx_legal_requirements_type_validation
    ON legal_requirements(requirement_type, validation_type);
CREATE INDEX idx_requirement_scopes_requirement
    ON requirement_scopes(requirement_id);
CREATE INDEX idx_requirement_scopes_product_form_market
    ON requirement_scopes(product_id, product_form_id, market_id);
CREATE INDEX idx_requirement_scopes_hs_code
    ON requirement_scopes(hs_code_id) WHERE hs_code_id IS NOT NULL;
CREATE INDEX idx_legal_limits_requirement
    ON legal_limits(requirement_id);
CREATE INDEX idx_legal_limits_substance_product_market
    ON legal_limits(substance_id, product_id, market_id);
CREATE INDEX idx_legal_limits_effective_dates
    ON legal_limits(effective_from, effective_to);
CREATE INDEX idx_legal_citations_section
    ON legal_citations(section_id);
CREATE INDEX idx_legal_citations_requirement
    ON legal_citations(requirement_id) WHERE requirement_id IS NOT NULL;
CREATE INDEX idx_market_entity_approvals_entity_market
    ON market_entity_approvals(registered_entity_id, market_id);
CREATE INDEX idx_market_entity_approvals_market_status
    ON market_entity_approvals(market_id, approval_status);
CREATE INDEX idx_lab_test_results_regulated_substance
    ON lab_test_results(regulated_substance_id) WHERE regulated_substance_id IS NOT NULL;
