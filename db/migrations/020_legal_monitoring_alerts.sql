CREATE TABLE regulation_changes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    legal_document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE RESTRICT,
    from_version_id uuid,
    to_version_id uuid NOT NULL,
    change_type text NOT NULL
        CHECK (change_type IN ('NEW', 'AMENDMENT', 'REPLACEMENT', 'REPEAL', 'EXPIRATION')),
    status text NOT NULL DEFAULT 'DETECTED'
        CHECK (status IN ('DETECTED', 'ANALYZING', 'CONFIRMED', 'IGNORED')),
    summary text,
    detected_at timestamptz NOT NULL DEFAULT now(),
    confirmed_at timestamptz,
    confirmed_by uuid REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE NULLS NOT DISTINCT (legal_document_id, from_version_id, to_version_id),
    UNIQUE (id, from_version_id, to_version_id),
    FOREIGN KEY (legal_document_id, from_version_id)
        REFERENCES legal_document_versions(legal_document_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (legal_document_id, to_version_id)
        REFERENCES legal_document_versions(legal_document_id, id) ON DELETE RESTRICT,
    CHECK (from_version_id IS NULL OR from_version_id <> to_version_id),
    CHECK ((change_type = 'NEW') = (from_version_id IS NULL)),
    CHECK (summary IS NULL OR length(btrim(summary)) > 0),
    CHECK ((status = 'CONFIRMED') = (confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL))
);

CREATE TABLE regulation_change_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    regulation_change_id uuid NOT NULL REFERENCES regulation_changes(id) ON DELETE CASCADE,
    change_category text NOT NULL
        CHECK (change_category IN (
            'REQUIREMENT_ADDED', 'REQUIREMENT_REMOVED', 'REQUIREMENT_MODIFIED',
            'LIMIT_INCREASED', 'LIMIT_DECREASED', 'SCOPE_CHANGED',
            'EFFECTIVE_DATE_CHANGED', 'OTHER'
        )),
    old_requirement_id uuid REFERENCES legal_requirements(id) ON DELETE RESTRICT,
    new_requirement_id uuid REFERENCES legal_requirements(id) ON DELETE RESTRICT,
    old_legal_limit_id uuid REFERENCES legal_limits(id) ON DELETE RESTRICT,
    new_legal_limit_id uuid REFERENCES legal_limits(id) ON DELETE RESTRICT,
    severity text NOT NULL CHECK (severity IN ('INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    change_summary text NOT NULL,
    requires_reassessment boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (regulation_change_id, id),
    CHECK (length(btrim(change_summary)) > 0),
    CHECK (
        (change_category = 'REQUIREMENT_ADDED'
            AND old_requirement_id IS NULL AND new_requirement_id IS NOT NULL
            AND old_legal_limit_id IS NULL AND new_legal_limit_id IS NULL)
        OR (change_category = 'REQUIREMENT_REMOVED'
            AND old_requirement_id IS NOT NULL AND new_requirement_id IS NULL
            AND old_legal_limit_id IS NULL AND new_legal_limit_id IS NULL)
        OR (change_category IN ('REQUIREMENT_MODIFIED', 'SCOPE_CHANGED', 'EFFECTIVE_DATE_CHANGED')
            AND old_requirement_id IS NOT NULL AND new_requirement_id IS NOT NULL
            AND old_legal_limit_id IS NULL AND new_legal_limit_id IS NULL)
        OR (change_category IN ('LIMIT_INCREASED', 'LIMIT_DECREASED')
            AND old_requirement_id IS NULL AND new_requirement_id IS NULL
            AND old_legal_limit_id IS NOT NULL AND new_legal_limit_id IS NOT NULL)
        OR (change_category = 'OTHER'
            AND num_nonnulls(old_requirement_id, new_requirement_id,
                             old_legal_limit_id, new_legal_limit_id) > 0)
    )
);

CREATE FUNCTION validate_regulation_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    from_number integer;
    to_number integer;
    to_parent uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status IN ('CONFIRMED', 'IGNORED') THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal regulation changes are immutable';
        END IF;
        RETURN OLD;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status IN ('CONFIRMED', 'IGNORED') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal regulation changes are immutable';
    END IF;

    SELECT version_number, previous_version_id INTO to_number, to_parent
    FROM legal_document_versions
    WHERE legal_document_id = NEW.legal_document_id AND id = NEW.to_version_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'to version must belong to the regulation legal document';
    END IF;
    IF NEW.from_version_id IS NOT NULL THEN
        SELECT version_number INTO from_number
        FROM legal_document_versions
        WHERE legal_document_id = NEW.legal_document_id AND id = NEW.from_version_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'from version must belong to the regulation legal document';
        END IF;
        IF to_number <= from_number OR to_parent IS DISTINCT FROM NEW.from_version_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'version comparison must follow direct newer-version lineage';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF (NEW.legal_document_id, NEW.from_version_id, NEW.to_version_id,
            NEW.change_type, NEW.detected_at, NEW.created_at)
           IS DISTINCT FROM
           (OLD.legal_document_id, OLD.from_version_id, OLD.to_version_id,
            OLD.change_type, OLD.detected_at, OLD.created_at) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'regulation change version provenance is immutable';
        END IF;
        IF NEW.status <> OLD.status AND NOT (
            (OLD.status = 'DETECTED' AND NEW.status IN ('ANALYZING', 'IGNORED'))
            OR (OLD.status = 'ANALYZING' AND NEW.status IN ('CONFIRMED', 'IGNORED'))
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid regulation change status transition';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_regulation_change
BEFORE INSERT OR UPDATE OR DELETE ON regulation_changes
FOR EACH ROW EXECUTE FUNCTION validate_regulation_change();

CREATE FUNCTION legal_requirement_version(target_requirement_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT section_record.version_id
    FROM legal_requirements requirement_record
    JOIN legal_sections section_record ON section_record.id = requirement_record.section_id
    WHERE requirement_record.id = target_requirement_id;
$$;

CREATE FUNCTION legal_limit_version(target_limit_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT section_record.version_id
    FROM legal_limits limit_record
    JOIN legal_requirements requirement_record ON requirement_record.id = limit_record.requirement_id
    JOIN legal_sections section_record ON section_record.id = requirement_record.section_id
    WHERE limit_record.id = target_limit_id;
$$;

CREATE FUNCTION legal_requirement_structured_fingerprint(target_requirement_id uuid)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT md5(concat_ws('|',
        requirement_record.title,
        requirement_record.requirement_text,
        requirement_record.requirement_type,
        requirement_record.obligation_level,
        requirement_record.validation_type,
        requirement_record.severity_default,
        requirement_record.priority::text,
        requirement_record.effective_from::text,
        requirement_record.effective_to::text,
        coalesce((
            SELECT jsonb_agg(jsonb_build_array(
                scope_record.product_id, scope_record.product_form_id,
                scope_record.hs_code_id, scope_record.origin_country_id,
                scope_record.destination_country_id, scope_record.market_id,
                scope_record.priority
            ) ORDER BY scope_record.product_id, scope_record.product_form_id,
                       scope_record.hs_code_id, scope_record.origin_country_id,
                       scope_record.destination_country_id, scope_record.market_id,
                       scope_record.priority)::text
            FROM requirement_scopes scope_record
            WHERE scope_record.requirement_id = requirement_record.id
        ), '[]'),
        coalesce((
            SELECT jsonb_agg(jsonb_build_array(
                limit_record.substance_id, limit_record.product_id,
                limit_record.product_form_id, limit_record.hs_code_id,
                limit_record.market_id, limit_record.limit_type,
                limit_record.operator, limit_record.normalized_limit_value,
                limit_record.normalized_unit_id, limit_record.priority,
                limit_record.effective_from, limit_record.effective_to
            ) ORDER BY limit_record.substance_id, limit_record.product_id,
                       limit_record.product_form_id, limit_record.hs_code_id,
                       limit_record.market_id, limit_record.limit_type,
                       limit_record.priority)::text
            FROM legal_limits limit_record
            WHERE limit_record.requirement_id = requirement_record.id
        ), '[]')
    ))
    FROM legal_requirements requirement_record
    WHERE requirement_record.id = target_requirement_id;
$$;

CREATE FUNCTION validate_regulation_change_item()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    change_record regulation_changes%ROWTYPE;
    old_version uuid;
    new_version uuid;
    old_limit_record legal_limits%ROWTYPE;
    new_limit_record legal_limits%ROWTYPE;
BEGIN
    SELECT * INTO change_record FROM regulation_changes
    WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.regulation_change_id ELSE NEW.regulation_change_id END;
    IF change_record.status IN ('CONFIRMED', 'IGNORED') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal regulation change items are immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

    IF NEW.old_requirement_id IS NOT NULL THEN
        old_version := legal_requirement_version(NEW.old_requirement_id);
        IF old_version IS DISTINCT FROM change_record.from_version_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'old requirement must belong to the from version';
        END IF;
    END IF;
    IF NEW.new_requirement_id IS NOT NULL THEN
        new_version := legal_requirement_version(NEW.new_requirement_id);
        IF new_version IS DISTINCT FROM change_record.to_version_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'new requirement must belong to the to version';
        END IF;
    END IF;
    IF NEW.old_legal_limit_id IS NOT NULL THEN
        old_version := legal_limit_version(NEW.old_legal_limit_id);
        IF old_version IS DISTINCT FROM change_record.from_version_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'old limit must belong to the from version';
        END IF;
    END IF;
    IF NEW.new_legal_limit_id IS NOT NULL THEN
        new_version := legal_limit_version(NEW.new_legal_limit_id);
        IF new_version IS DISTINCT FROM change_record.to_version_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'new limit must belong to the to version';
        END IF;
    END IF;

    IF NEW.change_category IN ('LIMIT_INCREASED', 'LIMIT_DECREASED') THEN
        SELECT * INTO old_limit_record FROM legal_limits WHERE id = NEW.old_legal_limit_id;
        SELECT * INTO new_limit_record FROM legal_limits WHERE id = NEW.new_legal_limit_id;
        IF old_limit_record.normalized_unit_id <> new_limit_record.normalized_unit_id
           OR old_limit_record.substance_id IS DISTINCT FROM new_limit_record.substance_id
           OR old_limit_record.product_id IS DISTINCT FROM new_limit_record.product_id
           OR old_limit_record.product_form_id IS DISTINCT FROM new_limit_record.product_form_id
           OR old_limit_record.hs_code_id IS DISTINCT FROM new_limit_record.hs_code_id
           OR old_limit_record.market_id IS DISTINCT FROM new_limit_record.market_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'limit comparison requires equivalent structured scope and normalized unit';
        END IF;
        IF (NEW.change_category = 'LIMIT_INCREASED'
            AND new_limit_record.normalized_limit_value <= old_limit_record.normalized_limit_value)
           OR (NEW.change_category = 'LIMIT_DECREASED'
            AND new_limit_record.normalized_limit_value >= old_limit_record.normalized_limit_value) THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'limit change category does not match normalized values';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_regulation_change_item
BEFORE INSERT OR UPDATE OR DELETE ON regulation_change_items
FOR EACH ROW EXECUTE FUNCTION validate_regulation_change_item();

CREATE FUNCTION compare_legal_versions(
    target_from_version_id uuid,
    target_to_version_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    from_document_id uuid;
    to_document_id uuid;
    new_change_id uuid;
BEGIN
    SELECT legal_document_id INTO to_document_id
    FROM legal_document_versions WHERE id = target_to_version_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'to legal version does not exist';
    END IF;
    IF target_from_version_id IS NOT NULL THEN
        SELECT legal_document_id INTO from_document_id
        FROM legal_document_versions WHERE id = target_from_version_id;
        IF from_document_id IS DISTINCT FROM to_document_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'legal version comparison cannot cross documents';
        END IF;
    END IF;
    INSERT INTO regulation_changes(
        legal_document_id, from_version_id, to_version_id,
        change_type, status, summary
    ) VALUES (
        to_document_id, target_from_version_id, target_to_version_id,
        CASE WHEN target_from_version_id IS NULL THEN 'NEW' ELSE 'AMENDMENT' END,
        'ANALYZING',
        'Structured comparison pending manual confirmation'
    ) RETURNING id INTO new_change_id;

    IF target_from_version_id IS NOT NULL THEN
        INSERT INTO regulation_change_items(
            regulation_change_id, change_category, old_requirement_id,
            severity, change_summary, requires_reassessment
        )
        SELECT new_change_id, 'REQUIREMENT_REMOVED', old_requirement.id,
               old_requirement.severity_default,
               'Structured requirement exists only in the from version', true
        FROM legal_requirements old_requirement
        JOIN legal_sections old_section ON old_section.id = old_requirement.section_id
        WHERE old_section.version_id = target_from_version_id
          AND NOT EXISTS (
              SELECT 1
              FROM legal_requirements new_requirement
              JOIN legal_sections new_section ON new_section.id = new_requirement.section_id
              WHERE new_section.version_id = target_to_version_id
                AND legal_requirement_structured_fingerprint(new_requirement.id)
                    = legal_requirement_structured_fingerprint(old_requirement.id)
          );
    END IF;

    INSERT INTO regulation_change_items(
        regulation_change_id, change_category, new_requirement_id,
        severity, change_summary, requires_reassessment
    )
    SELECT new_change_id, 'REQUIREMENT_ADDED', new_requirement.id,
           new_requirement.severity_default,
           'Structured requirement exists only in the to version', true
    FROM legal_requirements new_requirement
    JOIN legal_sections new_section ON new_section.id = new_requirement.section_id
    WHERE new_section.version_id = target_to_version_id
      AND (
          target_from_version_id IS NULL OR NOT EXISTS (
              SELECT 1
              FROM legal_requirements old_requirement
              JOIN legal_sections old_section ON old_section.id = old_requirement.section_id
              WHERE old_section.version_id = target_from_version_id
                AND legal_requirement_structured_fingerprint(old_requirement.id)
                    = legal_requirement_structured_fingerprint(new_requirement.id)
          )
      );
    RETURN new_change_id;
END;
$$;

CREATE FUNCTION confirm_regulation_change(
    target_change_id uuid,
    target_confirmed_by uuid,
    target_summary text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    to_status text;
BEGIN
    SELECT version_record.status INTO to_status
    FROM regulation_changes change_record
    JOIN legal_document_versions version_record ON version_record.id = change_record.to_version_id
    WHERE change_record.id = target_change_id;
    IF to_status NOT IN ('APPROVED', 'ACTIVE', 'UPCOMING') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'only reviewed legal versions can confirm a regulation change';
    END IF;
    UPDATE regulation_changes
    SET status = 'CONFIRMED',
        summary = coalesce(target_summary, summary),
        confirmed_at = clock_timestamp(),
        confirmed_by = target_confirmed_by,
        updated_at = clock_timestamp()
    WHERE id = target_change_id AND status = 'ANALYZING';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'only an analyzing regulation change can be confirmed';
    END IF;
END;
$$;

CREATE TABLE batch_legal_impacts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    change_item_id uuid NOT NULL REFERENCES regulation_change_items(id) ON DELETE RESTRICT,
    impact_status text NOT NULL
        CHECK (impact_status IN ('POTENTIALLY_AFFECTED', 'AFFECTED', 'NOT_AFFECTED', 'REVIEW_REQUIRED')),
    impact_reason text,
    previous_check_id uuid,
    recommended_action text
        CHECK (recommended_action IN ('NONE', 'REVIEW_DOCUMENTS', 'NEW_LAB_TEST', 'RECHECK', 'MANUAL_REVIEW')),
    assessed_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, batch_id, id),
    UNIQUE (organization_id, batch_id, change_item_id),
    FOREIGN KEY (organization_id, batch_id)
        REFERENCES export_batches(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, batch_id, previous_check_id)
        REFERENCES compliance_checks(organization_id, batch_id, id) ON DELETE RESTRICT,
    CHECK (impact_reason IS NULL OR length(btrim(impact_reason)) > 0)
);

CREATE FUNCTION assess_batch_legal_impact(
    target_organization_id uuid,
    target_batch_id uuid,
    target_change_item_id uuid,
    target_previous_check_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    item_record record;
    batch_record export_batches%ROWTYPE;
    target_requirement_id uuid;
    effective_date date;
    timing_date date;
    scope_count integer;
    exact_match boolean;
    ambiguous_match boolean;
    resolved_status text;
    resolved_reason text;
    resolved_action text;
    impact_id_value uuid;
BEGIN
    SELECT item.*, change_record.status AS change_status,
           change_record.to_version_id, version_record.effective_from AS version_effective_from
    INTO item_record
    FROM regulation_change_items item
    JOIN regulation_changes change_record ON change_record.id = item.regulation_change_id
    JOIN legal_document_versions version_record ON version_record.id = change_record.to_version_id
    WHERE item.id = target_change_item_id;
    IF NOT FOUND OR item_record.change_status <> 'CONFIRMED' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'impact assessment requires a confirmed regulation change item';
    END IF;
    SELECT * INTO batch_record FROM export_batches
    WHERE organization_id = target_organization_id AND id = target_batch_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'batch impact requires a same-tenant batch';
    END IF;

    target_requirement_id := coalesce(
        item_record.new_requirement_id,
        (SELECT requirement_id FROM legal_limits WHERE id = item_record.new_legal_limit_id),
        item_record.old_requirement_id,
        (SELECT requirement_id FROM legal_limits WHERE id = item_record.old_legal_limit_id)
    );
    effective_date := coalesce(
        (SELECT effective_from FROM legal_limits WHERE id = item_record.new_legal_limit_id),
        (SELECT effective_from FROM legal_requirements WHERE id = item_record.new_requirement_id),
        item_record.version_effective_from
    );
    timing_date := coalesce(batch_record.actual_export_date, batch_record.planned_export_date);

    IF effective_date IS NULL OR timing_date IS NULL THEN
        resolved_status := 'REVIEW_REQUIRED';
        resolved_reason := 'Effective date or batch export date is missing';
        resolved_action := 'MANUAL_REVIEW';
    ELSIF timing_date < effective_date THEN
        resolved_status := 'NOT_AFFECTED';
        resolved_reason := 'Batch export date is before the new legal effective date';
        resolved_action := 'NONE';
    ELSIF target_requirement_id IS NULL THEN
        resolved_status := 'REVIEW_REQUIRED';
        resolved_reason := 'Change item has no resolvable requirement scope';
        resolved_action := 'MANUAL_REVIEW';
    ELSE
        SELECT count(*) INTO scope_count FROM requirement_scopes
        WHERE requirement_id = target_requirement_id;
        SELECT EXISTS (
            SELECT 1
            FROM export_batch_items batch_item
            JOIN requirement_scopes scope_record
              ON scope_record.requirement_id = target_requirement_id
             AND (scope_record.product_id IS NULL OR scope_record.product_id = batch_item.product_id)
             AND (scope_record.product_form_id IS NULL OR scope_record.product_form_id = batch_item.product_form_id)
             AND (scope_record.hs_code_id IS NULL OR scope_record.hs_code_id = batch_item.hs_code_id)
             AND (scope_record.origin_country_id IS NULL OR scope_record.origin_country_id = batch_record.origin_country_id)
             AND (scope_record.destination_country_id IS NULL OR scope_record.destination_country_id = batch_record.destination_country_id)
             AND (scope_record.market_id IS NULL OR scope_record.market_id = batch_record.market_id)
            WHERE batch_item.organization_id = target_organization_id
              AND batch_item.batch_id = target_batch_id
        ) INTO exact_match;
        SELECT EXISTS (
            SELECT 1
            FROM export_batch_items batch_item
            JOIN requirement_scopes scope_record
              ON scope_record.requirement_id = target_requirement_id
             AND (scope_record.product_id IS NULL OR scope_record.product_id = batch_item.product_id)
             AND (scope_record.product_form_id IS NULL OR scope_record.product_form_id = batch_item.product_form_id)
             AND scope_record.hs_code_id IS NOT NULL
             AND batch_item.hs_code_id IS NULL
             AND (scope_record.origin_country_id IS NULL OR scope_record.origin_country_id = batch_record.origin_country_id)
             AND (scope_record.destination_country_id IS NULL OR scope_record.destination_country_id = batch_record.destination_country_id)
             AND (scope_record.market_id IS NULL OR scope_record.market_id = batch_record.market_id)
            WHERE batch_item.organization_id = target_organization_id
              AND batch_item.batch_id = target_batch_id
        ) INTO ambiguous_match;

        IF exact_match THEN
            resolved_status := 'AFFECTED';
            resolved_reason := 'Batch matches at least one complete structured scope row';
            resolved_action := CASE WHEN item_record.requires_reassessment THEN 'RECHECK' ELSE 'REVIEW_DOCUMENTS' END;
        ELSIF ambiguous_match OR scope_count = 0 THEN
            resolved_status := 'REVIEW_REQUIRED';
            resolved_reason := CASE WHEN scope_count = 0
                THEN 'Requirement has no explicit scope row'
                ELSE 'Batch data is incomplete for a potentially matching scope' END;
            resolved_action := 'MANUAL_REVIEW';
        ELSE
            resolved_status := 'NOT_AFFECTED';
            resolved_reason := 'Batch does not match any structured scope row';
            resolved_action := 'NONE';
        END IF;
    END IF;

    INSERT INTO batch_legal_impacts(
        organization_id, batch_id, change_item_id, impact_status,
        impact_reason, previous_check_id, recommended_action
    ) VALUES (
        target_organization_id, target_batch_id, target_change_item_id,
        resolved_status, resolved_reason, target_previous_check_id, resolved_action
    )
    ON CONFLICT (organization_id, batch_id, change_item_id) DO UPDATE SET
        impact_status = EXCLUDED.impact_status,
        impact_reason = EXCLUDED.impact_reason,
        previous_check_id = EXCLUDED.previous_check_id,
        recommended_action = EXCLUDED.recommended_action,
        assessed_at = clock_timestamp(),
        updated_at = clock_timestamp()
    RETURNING id INTO impact_id_value;
    RETURN impact_id_value;
END;
$$;

CREATE TABLE alerts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    batch_id uuid,
    regulation_change_id uuid REFERENCES regulation_changes(id) ON DELETE RESTRICT,
    change_item_id uuid REFERENCES regulation_change_items(id) ON DELETE RESTRICT,
    impact_id uuid,
    alert_type text NOT NULL
        CHECK (alert_type IN ('LEGAL_CHANGE', 'BATCH_AT_RISK', 'DOCUMENT_EXPIRING', 'COMPLIANCE_FAILURE', 'REMEDIATION_DUE', 'SYSTEM')),
    severity text NOT NULL CHECK (severity IN ('INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    title text NOT NULL,
    message text NOT NULL,
    status text NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'ACKNOWLEDGED', 'RESOLVED', 'DISMISSED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    acknowledged_at timestamptz,
    resolved_at timestamptz,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, batch_id)
        REFERENCES export_batches(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, batch_id, impact_id)
        REFERENCES batch_legal_impacts(organization_id, batch_id, id) ON DELETE RESTRICT,
    CHECK (length(btrim(title)) > 0),
    CHECK (length(btrim(message)) > 0),
    CHECK (status <> 'ACKNOWLEDGED' OR acknowledged_at IS NOT NULL),
    CHECK (status NOT IN ('RESOLVED', 'DISMISSED') OR resolved_at IS NOT NULL),
    CHECK (alert_type <> 'BATCH_AT_RISK' OR (
        batch_id IS NOT NULL AND regulation_change_id IS NOT NULL
        AND change_item_id IS NOT NULL AND impact_id IS NOT NULL
    ))
);

CREATE UNIQUE INDEX alerts_impact_type_unique
    ON alerts (organization_id, impact_id, alert_type)
    WHERE impact_id IS NOT NULL;

CREATE FUNCTION validate_alert_linkage()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    impact_item_id uuid;
    item_change_id uuid;
BEGIN
    IF NEW.impact_id IS NOT NULL THEN
        SELECT change_item_id INTO impact_item_id FROM batch_legal_impacts
        WHERE organization_id = NEW.organization_id
          AND batch_id = NEW.batch_id
          AND id = NEW.impact_id;
        SELECT regulation_change_id INTO item_change_id FROM regulation_change_items
        WHERE id = NEW.change_item_id;
        IF impact_item_id IS DISTINCT FROM NEW.change_item_id
           OR item_change_id IS DISTINCT FROM NEW.regulation_change_id THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'alert change and impact linkage is inconsistent';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF (NEW.organization_id, NEW.batch_id, NEW.regulation_change_id,
            NEW.change_item_id, NEW.impact_id, NEW.alert_type,
            NEW.severity, NEW.title, NEW.message, NEW.created_at)
           IS DISTINCT FROM
           (OLD.organization_id, OLD.batch_id, OLD.regulation_change_id,
            OLD.change_item_id, OLD.impact_id, OLD.alert_type,
            OLD.severity, OLD.title, OLD.message, OLD.created_at) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'alert business event content is immutable';
        END IF;
        IF NEW.status <> OLD.status AND NOT (
            (OLD.status = 'OPEN' AND NEW.status IN ('ACKNOWLEDGED', 'RESOLVED', 'DISMISSED'))
            OR (OLD.status = 'ACKNOWLEDGED' AND NEW.status IN ('RESOLVED', 'DISMISSED'))
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid alert status transition';
        END IF;
        IF OLD.status IN ('RESOLVED', 'DISMISSED') THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal alert history is immutable';
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'alerts are persistent business events';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_alert_linkage
BEFORE INSERT OR UPDATE OR DELETE ON alerts
FOR EACH ROW EXECUTE FUNCTION validate_alert_linkage();

CREATE TABLE alert_recipients (
    organization_id uuid NOT NULL,
    alert_id uuid NOT NULL,
    user_id uuid NOT NULL,
    is_read boolean NOT NULL DEFAULT false,
    read_at timestamptz,
    acknowledged_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, alert_id, user_id),
    FOREIGN KEY (organization_id, alert_id)
        REFERENCES alerts(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, user_id)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT,
    CHECK (is_read = (read_at IS NOT NULL))
);

CREATE FUNCTION validate_alert_recipient()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NOT EXISTS (
            SELECT 1 FROM organization_members
            WHERE organization_id = NEW.organization_id
              AND user_id = NEW.user_id AND status = 'ACTIVE'
        ) OR NOT user_has_organization_permission(
            NEW.organization_id, NEW.user_id, 'ALERT_READ'
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'alert recipient must be an active permitted organization member';
        END IF;
    ELSE
        IF (NEW.organization_id, NEW.alert_id, NEW.user_id, NEW.created_at)
           IS DISTINCT FROM
           (OLD.organization_id, OLD.alert_id, OLD.user_id, OLD.created_at) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'alert recipient identity is immutable';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_alert_recipient
BEFORE INSERT OR UPDATE ON alert_recipients
FOR EACH ROW EXECUTE FUNCTION validate_alert_recipient();

CREATE TABLE notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    alert_id uuid,
    channel text NOT NULL CHECK (channel IN ('IN_APP', 'EMAIL')),
    title text NOT NULL,
    message text NOT NULL,
    status text NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'SENT', 'DELIVERED', 'FAILED', 'READ', 'CANCELLED')),
    idempotency_key text,
    attempt_number integer NOT NULL DEFAULT 1,
    max_attempts integer NOT NULL DEFAULT 3,
    next_retry_at timestamptz,
    sent_at timestamptz,
    delivered_at timestamptz,
    read_at timestamptz,
    last_error_code text,
    failure_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, user_id)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, alert_id)
        REFERENCES alerts(organization_id, id) ON DELETE RESTRICT,
    CHECK (length(btrim(title)) > 0),
    CHECK (length(btrim(message)) > 0),
    CHECK (idempotency_key IS NULL OR length(btrim(idempotency_key)) > 0),
    CHECK (attempt_number >= 1 AND max_attempts >= 1 AND attempt_number <= max_attempts),
    CHECK (status NOT IN ('SENT', 'DELIVERED', 'READ') OR sent_at IS NOT NULL),
    CHECK (status NOT IN ('DELIVERED', 'READ') OR delivered_at IS NOT NULL),
    CHECK ((status = 'READ') = (read_at IS NOT NULL))
);

CREATE UNIQUE INDEX uq_notifications_organization_idempotency
    ON notifications(organization_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE FUNCTION validate_notification_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'notification delivery history cannot be deleted';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'PENDING' THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'new notifications must start pending';
        END IF;
        RETURN NEW;
    END IF;
    IF (NEW.organization_id, NEW.user_id, NEW.alert_id, NEW.channel,
        NEW.title, NEW.message, NEW.idempotency_key, NEW.max_attempts,
        NEW.created_at)
       IS DISTINCT FROM
       (OLD.organization_id, OLD.user_id, OLD.alert_id, OLD.channel,
        OLD.title, OLD.message, OLD.idempotency_key, OLD.max_attempts,
        OLD.created_at) THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'notification recipient and delivery content are immutable';
    END IF;
    IF OLD.status IN ('READ', 'CANCELLED') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal notification history is immutable';
    END IF;
    IF NEW.status <> OLD.status AND NOT (
        (OLD.status = 'PENDING' AND NEW.status IN ('SENT', 'FAILED', 'CANCELLED'))
        OR (OLD.status = 'SENT' AND NEW.status IN ('DELIVERED', 'FAILED'))
        OR (OLD.status = 'DELIVERED' AND NEW.status = 'READ')
        OR (OLD.status = 'FAILED' AND NEW.status = 'PENDING'
            AND NEW.attempt_number = OLD.attempt_number + 1)
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid notification lifecycle transition';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_notification_lifecycle
BEFORE INSERT OR UPDATE OR DELETE ON notifications
FOR EACH ROW EXECUTE FUNCTION validate_notification_lifecycle();

CREATE FUNCTION create_batch_risk_alerts(target_regulation_change_id uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    created_count integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM regulation_changes
        WHERE id = target_regulation_change_id AND status = 'CONFIRMED'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'alerts require a confirmed regulation change';
    END IF;
    WITH inserted AS (
        INSERT INTO alerts(
            organization_id, batch_id, regulation_change_id, change_item_id,
            impact_id, alert_type, severity, title, message
        )
        SELECT impact.organization_id, impact.batch_id, item.regulation_change_id,
               impact.change_item_id, impact.id, 'BATCH_AT_RISK', item.severity,
               'Legal change may affect batch ' || batch_record.batch_code,
               'Review the structured legal impact assessment for this batch.'
        FROM batch_legal_impacts impact
        JOIN regulation_change_items item ON item.id = impact.change_item_id
        JOIN export_batches batch_record
          ON batch_record.organization_id = impact.organization_id
         AND batch_record.id = impact.batch_id
        WHERE item.regulation_change_id = target_regulation_change_id
          AND impact.impact_status IN ('AFFECTED', 'POTENTIALLY_AFFECTED', 'REVIEW_REQUIRED')
        ON CONFLICT (organization_id, impact_id, alert_type)
            WHERE impact_id IS NOT NULL
        DO NOTHING
        RETURNING id
    ) SELECT count(*) INTO created_count FROM inserted;

    INSERT INTO alert_recipients(organization_id, alert_id, user_id)
    SELECT alert_record.organization_id, alert_record.id, member_record.user_id
    FROM alerts alert_record
    JOIN regulation_change_items item ON item.id = alert_record.change_item_id
    JOIN organization_members member_record
      ON member_record.organization_id = alert_record.organization_id
     AND member_record.status = 'ACTIVE'
    WHERE item.regulation_change_id = target_regulation_change_id
      AND user_has_organization_permission(
          alert_record.organization_id, member_record.user_id, 'ALERT_READ'
      )
    ON CONFLICT DO NOTHING;
    RETURN created_count;
END;
$$;

CREATE FUNCTION create_in_app_notifications_for_alert(target_alert_id uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    created_count integer;
BEGIN
    WITH inserted AS (
        INSERT INTO notifications(
            organization_id, user_id, alert_id, channel, title, message,
            idempotency_key, attempt_number, max_attempts
        )
        SELECT recipient.organization_id, recipient.user_id, alert_record.id,
               'IN_APP', alert_record.title, alert_record.message,
               'IN_APP:' || alert_record.id::text || ':' || recipient.user_id::text,
               1, 3
        FROM alert_recipients recipient
        JOIN alerts alert_record
          ON alert_record.organization_id = recipient.organization_id
         AND alert_record.id = recipient.alert_id
        WHERE alert_record.id = target_alert_id
        ON CONFLICT (organization_id, idempotency_key) WHERE idempotency_key IS NOT NULL
        DO NOTHING
        RETURNING id
    ) SELECT count(*) INTO created_count FROM inserted;
    RETURN created_count;
END;
$$;

CREATE FUNCTION acknowledge_alert(
    target_organization_id uuid,
    target_alert_id uuid,
    target_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT user_has_organization_permission(
        target_organization_id, target_user_id, 'ALERT_ACKNOWLEDGE'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'user lacks alert acknowledgement permission';
    END IF;
    UPDATE alerts
    SET status = 'ACKNOWLEDGED', acknowledged_at = clock_timestamp()
    WHERE organization_id = target_organization_id
      AND id = target_alert_id
      AND status = 'OPEN';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'only an open alert can be acknowledged';
    END IF;
    UPDATE alert_recipients
    SET acknowledged_at = clock_timestamp()
    WHERE organization_id = target_organization_id
      AND alert_id = target_alert_id
      AND user_id = target_user_id;
END;
$$;

CREATE INDEX idx_regulation_changes_document_detected
    ON regulation_changes(legal_document_id, detected_at DESC);
CREATE INDEX idx_regulation_changes_status
    ON regulation_changes(status, detected_at);
CREATE INDEX idx_change_items_change_category
    ON regulation_change_items(regulation_change_id, change_category);
CREATE INDEX idx_batch_impacts_change_status
    ON batch_legal_impacts(change_item_id, impact_status);
CREATE INDEX idx_batch_impacts_organization_status
    ON batch_legal_impacts(organization_id, impact_status, assessed_at);
CREATE INDEX idx_alerts_organization_status
    ON alerts(organization_id, status, created_at);
CREATE INDEX idx_alerts_regulation_change
    ON alerts(regulation_change_id) WHERE regulation_change_id IS NOT NULL;
CREATE INDEX idx_alert_recipients_user_read
    ON alert_recipients(organization_id, user_id, is_read);
CREATE INDEX idx_notifications_user_status
    ON notifications(organization_id, user_id, status, created_at);
CREATE INDEX idx_notifications_retry
    ON notifications(status, next_retry_at) WHERE status IN ('PENDING', 'FAILED');
