CREATE FUNCTION user_has_organization_permission(
    target_organization_id uuid,
    target_user_id uuid,
    target_permission_code text
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM organization_members member_record
        JOIN organization_member_roles member_role
          ON member_role.organization_id = member_record.organization_id
         AND member_role.organization_member_id = member_record.id
        JOIN role_permissions role_permission ON role_permission.role_id = member_role.role_id
        JOIN permissions permission_record ON permission_record.id = role_permission.permission_id
        WHERE member_record.organization_id = target_organization_id
          AND member_record.user_id = target_user_id
          AND member_record.status = 'ACTIVE'
          AND permission_record.code = target_permission_code
    );
$$;

CREATE TABLE compliance_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    check_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    parent_report_id uuid,
    version_number integer NOT NULL CHECK (version_number > 0),
    report_code text NOT NULL,
    status text NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED')),
    overall_result text NOT NULL
        CHECK (overall_result IN ('COMPLIANT', 'ACTION_REQUIRED', 'NON_COMPLIANT', 'MANUAL_REVIEW_REQUIRED')),
    title text NOT NULL,
    executive_summary text,
    submission_round integer NOT NULL DEFAULT 0 CHECK (submission_round >= 0),
    generated_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    generated_at timestamptz NOT NULL DEFAULT now(),
    submitted_at timestamptz,
    approved_at timestamptz,
    approved_by uuid REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, check_id),
    UNIQUE (organization_id, check_id, id),
    UNIQUE (organization_id, batch_id, id),
    UNIQUE (organization_id, batch_id, version_number),
    UNIQUE (organization_id, report_code),
    FOREIGN KEY (organization_id, batch_id)
        REFERENCES export_batches(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, batch_id, check_id)
        REFERENCES compliance_checks(organization_id, batch_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, batch_id, parent_report_id)
        REFERENCES compliance_reports(organization_id, batch_id, id) ON DELETE RESTRICT,
    CHECK (parent_report_id IS NULL OR parent_report_id <> id),
    CHECK (length(btrim(report_code)) > 0),
    CHECK (length(btrim(title)) > 0),
    CHECK (executive_summary IS NULL OR length(btrim(executive_summary)) > 0),
    CHECK ((status = 'DRAFT') = (submitted_at IS NULL)),
    CHECK ((status = 'APPROVED') = (approved_at IS NOT NULL AND approved_by IS NOT NULL)),
    CHECK (approved_at IS NULL OR submitted_at IS NULL OR approved_at >= submitted_at)
);

CREATE TABLE report_findings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    check_id uuid NOT NULL,
    report_id uuid NOT NULL,
    finding_id uuid NOT NULL,
    display_order integer NOT NULL CHECK (display_order >= 0),
    source_type_snapshot text NOT NULL CHECK (source_type_snapshot IN ('RULE_ENGINE', 'AI', 'MANUAL')),
    finding_type_snapshot text NOT NULL,
    title_snapshot text NOT NULL,
    description_snapshot text NOT NULL,
    severity_snapshot text NOT NULL CHECK (severity_snapshot IN ('INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    validation_status_snapshot text NOT NULL
        CHECK (validation_status_snapshot IN ('VALIDATED', 'MANUAL_REVIEW_REQUIRED', 'REJECTED')),
    actual_value_snapshot text,
    expected_value_snapshot text,
    unit_snapshot text,
    remediation_snapshot text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, report_id, id),
    UNIQUE (organization_id, report_id, finding_id),
    UNIQUE (organization_id, report_id, display_order),
    FOREIGN KEY (organization_id, check_id, report_id)
        REFERENCES compliance_reports(organization_id, check_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, check_id, finding_id)
        REFERENCES findings(organization_id, check_id, id) ON DELETE RESTRICT,
    CHECK (length(btrim(finding_type_snapshot)) > 0),
    CHECK (length(btrim(title_snapshot)) > 0),
    CHECK (length(btrim(description_snapshot)) > 0)
);

CREATE TABLE report_finding_citations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    report_finding_id uuid NOT NULL,
    source_citation_id uuid NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    citation_code_snapshot text NOT NULL,
    display_label_snapshot text NOT NULL,
    quote_excerpt_snapshot text,
    canonical_reference_snapshot text,
    legal_document_id uuid NOT NULL REFERENCES legal_documents(id) ON DELETE RESTRICT,
    legal_document_version_id uuid NOT NULL,
    legal_section_id uuid NOT NULL,
    legal_requirement_id uuid,
    legal_version_content_hash_snapshot text,
    source_file_checksum_snapshot text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, report_finding_id, source_citation_id),
    FOREIGN KEY (organization_id, report_finding_id)
        REFERENCES report_findings(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (legal_document_id, legal_document_version_id)
        REFERENCES legal_document_versions(legal_document_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (legal_document_version_id, legal_section_id)
        REFERENCES legal_sections(version_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (legal_section_id, legal_requirement_id)
        REFERENCES legal_requirements(section_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (legal_document_version_id, source_citation_id)
        REFERENCES legal_citations(version_id, id) ON DELETE RESTRICT,
    CHECK (length(btrim(citation_code_snapshot)) > 0),
    CHECK (length(btrim(display_label_snapshot)) > 0),
    CHECK (legal_version_content_hash_snapshot IS NULL OR legal_version_content_hash_snapshot ~ '^[0-9a-fA-F]{64}$'),
    CHECK (source_file_checksum_snapshot IS NULL OR source_file_checksum_snapshot ~ '^[0-9a-fA-F]{64}$')
);

CREATE TABLE report_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    report_id uuid NOT NULL,
    submission_round integer NOT NULL CHECK (submission_round > 0),
    reviewer_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    decision text NOT NULL CHECK (decision IN ('APPROVED', 'REJECTED')),
    comment text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, report_id, submission_round, reviewer_id),
    FOREIGN KEY (organization_id, report_id)
        REFERENCES compliance_reports(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, reviewer_id)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT,
    CHECK (comment IS NULL OR length(btrim(comment)) > 0)
);

CREATE FUNCTION validate_compliance_report()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    check_status text;
    check_result text;
    check_batch_id uuid;
    parent_check_id_value uuid;
    parent_check_for_report uuid;
    parent_version integer;
    parent_report_status text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'APPROVED' THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'approved compliance reports are immutable';
        END IF;
        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.status = 'APPROVED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'approved compliance reports are immutable';
    END IF;

    SELECT status, overall_result, batch_id, parent_check_id
    INTO check_status, check_result, check_batch_id, parent_check_id_value
    FROM compliance_checks
    WHERE organization_id = NEW.organization_id AND id = NEW.check_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'report requires an existing same-tenant compliance check';
    END IF;
    IF check_status <> 'COMPLETED' OR check_result IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'reports can only be generated from completed checks';
    END IF;
    IF NEW.batch_id <> check_batch_id OR NEW.overall_result <> check_result THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'report batch and result must match the completed check';
    END IF;

    IF parent_check_id_value IS NULL THEN
        IF NEW.parent_report_id IS NOT NULL OR NEW.version_number <> 1 THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'root check report must be version 1 without a parent report';
        END IF;
    ELSE
        IF NEW.parent_report_id IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 're-check report requires its parent check report';
        END IF;
        SELECT check_id, version_number, status
        INTO parent_check_for_report, parent_version, parent_report_status
        FROM compliance_reports
        WHERE organization_id = NEW.organization_id
          AND batch_id = NEW.batch_id
          AND id = NEW.parent_report_id;
        IF NOT FOUND OR parent_check_for_report <> parent_check_id_value
           OR parent_report_status <> 'APPROVED'
           OR NEW.version_number <> parent_version + 1 THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'report lineage requires the approved parent check report and next version';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'DRAFT' OR NEW.submission_round <> 0 THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'new reports must start as draft round zero';
        END IF;
    ELSE
        IF (NEW.organization_id, NEW.check_id, NEW.batch_id, NEW.parent_report_id,
            NEW.version_number, NEW.report_code, NEW.overall_result,
            NEW.generated_by, NEW.generated_at, NEW.created_at)
           IS DISTINCT FROM
           (OLD.organization_id, OLD.check_id, OLD.batch_id, OLD.parent_report_id,
            OLD.version_number, OLD.report_code, OLD.overall_result,
            OLD.generated_by, OLD.generated_at, OLD.created_at) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'report identity, lineage, result, and generation provenance are immutable';
        END IF;

        IF NEW.status = OLD.status THEN
            IF OLD.status = 'PENDING_APPROVAL' THEN
                RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending report content is locked until a decision';
            END IF;
        ELSIF OLD.status = 'DRAFT' AND NEW.status = 'PENDING_APPROVAL' THEN
            IF NEW.submission_round <> OLD.submission_round + 1 OR NEW.submitted_at IS NULL THEN
                RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'submission must increment the round and set submitted_at';
            END IF;
        ELSIF OLD.status = 'PENDING_APPROVAL' AND NEW.status = 'APPROVED' THEN
            IF NEW.submission_round <> OLD.submission_round
               OR NOT EXISTS (
                   SELECT 1 FROM report_approvals approval
                   WHERE approval.organization_id = NEW.organization_id
                     AND approval.report_id = NEW.id
                     AND approval.submission_round = NEW.submission_round
                     AND approval.reviewer_id = NEW.approved_by
                     AND approval.decision = 'APPROVED'
               ) THEN
                RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'approved state requires the current-round approval decision';
            END IF;
        ELSIF OLD.status = 'PENDING_APPROVAL' AND NEW.status = 'REJECTED' THEN
            IF NEW.submission_round <> OLD.submission_round
               OR NOT EXISTS (
                   SELECT 1 FROM report_approvals approval
                   WHERE approval.organization_id = NEW.organization_id
                     AND approval.report_id = NEW.id
                     AND approval.submission_round = NEW.submission_round
                     AND approval.decision = 'REJECTED'
               ) THEN
                RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'rejected state requires the current-round rejection decision';
            END IF;
        ELSIF OLD.status = 'REJECTED' AND NEW.status = 'DRAFT' THEN
            IF NEW.submission_round <> OLD.submission_round THEN
                RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'returning to draft must preserve submission history';
            END IF;
        ELSE
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid compliance report status transition';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_compliance_report
BEFORE INSERT OR UPDATE OR DELETE ON compliance_reports
FOR EACH ROW EXECUTE FUNCTION validate_compliance_report();

CREATE FUNCTION validate_report_finding_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    source_finding findings%ROWTYPE;
BEGIN
    SELECT * INTO source_finding FROM findings
    WHERE organization_id = NEW.organization_id
      AND check_id = NEW.check_id
      AND id = NEW.finding_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'report finding requires a finding from the report check';
    END IF;
    IF (NEW.source_type_snapshot, NEW.finding_type_snapshot, NEW.title_snapshot,
        NEW.description_snapshot, NEW.severity_snapshot, NEW.validation_status_snapshot,
        NEW.actual_value_snapshot, NEW.expected_value_snapshot, NEW.unit_snapshot,
        NEW.remediation_snapshot)
       IS DISTINCT FROM
       (source_finding.source_type, source_finding.finding_type, source_finding.title,
        source_finding.description, source_finding.severity, source_finding.validation_status,
        source_finding.actual_value, source_finding.expected_value, source_finding.unit_text,
        source_finding.remediation_hint) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'report finding snapshot must exactly match its source finding';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_report_finding_snapshot
BEFORE INSERT OR UPDATE ON report_findings
FOR EACH ROW EXECUTE FUNCTION validate_report_finding_snapshot();

CREATE FUNCTION validate_report_citation_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    report_check_id uuid;
    source_finding_id uuid;
    source_record record;
BEGIN
    SELECT report_record.check_id, report_finding.finding_id
    INTO report_check_id, source_finding_id
    FROM report_findings report_finding
    JOIN compliance_reports report_record
      ON report_record.organization_id = report_finding.organization_id
     AND report_record.id = report_finding.report_id
    WHERE report_finding.organization_id = NEW.organization_id
      AND report_finding.id = NEW.report_finding_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'report citation requires a same-tenant report finding';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM finding_citations
        WHERE finding_id = source_finding_id AND citation_id = NEW.source_citation_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'report citation must come from the source finding citations';
    END IF;

    SELECT citation.citation_code, citation.display_label, citation.quote_excerpt,
           citation.canonical_reference, citation.section_id, citation.requirement_id,
           section_record.version_id, version_record.legal_document_id,
           version_record.content_hash
    INTO source_record
    FROM legal_citations citation
    JOIN legal_sections section_record
      ON section_record.id = citation.section_id
     AND section_record.version_id = citation.version_id
    JOIN legal_document_versions version_record ON version_record.id = section_record.version_id
    JOIN legal_documents document_record ON document_record.id = version_record.legal_document_id
    JOIN legal_sources source_record_table ON source_record_table.id = document_record.source_id
    WHERE citation.id = NEW.source_citation_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'source citation provenance is incomplete';
    END IF;
    IF (NEW.citation_code_snapshot, NEW.display_label_snapshot,
        NEW.quote_excerpt_snapshot, NEW.canonical_reference_snapshot,
        NEW.legal_document_id, NEW.legal_document_version_id,
        NEW.legal_section_id, NEW.legal_requirement_id,
        NEW.legal_version_content_hash_snapshot)
       IS DISTINCT FROM
       (source_record.citation_code, source_record.display_label,
        source_record.quote_excerpt, source_record.canonical_reference,
        source_record.legal_document_id, source_record.version_id,
        source_record.section_id, source_record.requirement_id,
        source_record.content_hash) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'report citation snapshot does not match exact legal provenance';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM compliance_check_legal_versions
        WHERE organization_id = NEW.organization_id
          AND check_id = report_check_id
          AND legal_document_version_id = NEW.legal_document_version_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'report citation legal version is outside the check snapshot';
    END IF;
    IF NEW.source_file_checksum_snapshot IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM legal_document_files
        WHERE version_id = NEW.legal_document_version_id
          AND checksum_sha256 = NEW.source_file_checksum_snapshot
          AND is_original
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'report citation source checksum does not match an original legal file';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_report_citation_snapshot
BEFORE INSERT OR UPDATE ON report_finding_citations
FOR EACH ROW EXECUTE FUNCTION validate_report_citation_snapshot();

CREATE FUNCTION protect_approved_report_children()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_report_id uuid;
    report_status text;
BEGIN
    IF TG_TABLE_NAME = 'report_findings' THEN
        target_report_id := CASE WHEN TG_OP = 'INSERT' THEN NEW.report_id ELSE OLD.report_id END;
    ELSIF TG_TABLE_NAME = 'report_finding_citations' THEN
        SELECT report_id INTO target_report_id FROM report_findings
        WHERE id = CASE WHEN TG_OP = 'INSERT' THEN NEW.report_finding_id ELSE OLD.report_finding_id END;
    ELSE
        target_report_id := CASE WHEN TG_OP = 'INSERT' THEN NEW.report_id ELSE OLD.report_id END;
    END IF;
    SELECT status INTO report_status FROM compliance_reports WHERE id = target_report_id;
    IF report_status = 'APPROVED' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'approved report snapshot and approvals are immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_approved_report_findings
BEFORE INSERT OR UPDATE OR DELETE ON report_findings
FOR EACH ROW EXECUTE FUNCTION protect_approved_report_children();
CREATE TRIGGER trg_protect_approved_report_citations
BEFORE INSERT OR UPDATE OR DELETE ON report_finding_citations
FOR EACH ROW EXECUTE FUNCTION protect_approved_report_children();
CREATE TRIGGER trg_protect_approved_report_approvals
BEFORE INSERT OR UPDATE OR DELETE ON report_approvals
FOR EACH ROW EXECUTE FUNCTION protect_approved_report_children();

CREATE FUNCTION validate_report_approval()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    report_status text;
    current_round integer;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'report approval history is append-only';
    END IF;
    SELECT status, submission_round INTO report_status, current_round
    FROM compliance_reports
    WHERE organization_id = NEW.organization_id AND id = NEW.report_id;
    IF report_status <> 'PENDING_APPROVAL' OR NEW.submission_round <> current_round THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'approval decision must target the pending current submission round';
    END IF;
    IF NOT user_has_organization_permission(NEW.organization_id, NEW.reviewer_id, 'REPORT_APPROVE') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'reviewer lacks report approval permission';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_report_approval
BEFORE INSERT OR UPDATE OR DELETE ON report_approvals
FOR EACH ROW EXECUTE FUNCTION validate_report_approval();

CREATE FUNCTION report_snapshot_is_complete(target_report_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM compliance_reports report_record
        JOIN findings finding_record ON finding_record.check_id = report_record.check_id
        LEFT JOIN report_findings report_finding
          ON report_finding.organization_id = report_record.organization_id
         AND report_finding.report_id = report_record.id
         AND report_finding.finding_id = finding_record.id
        WHERE report_record.id = target_report_id
          AND report_finding.id IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM report_findings report_finding
        JOIN compliance_reports report_record ON report_record.id = report_finding.report_id
        LEFT JOIN findings finding_record
          ON finding_record.organization_id = report_finding.organization_id
         AND finding_record.check_id = report_record.check_id
         AND finding_record.id = report_finding.finding_id
        WHERE report_finding.report_id = target_report_id
          AND finding_record.id IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM report_findings report_finding
        JOIN finding_citations finding_citation ON finding_citation.finding_id = report_finding.finding_id
        LEFT JOIN report_finding_citations report_citation
          ON report_citation.organization_id = report_finding.organization_id
         AND report_citation.report_finding_id = report_finding.id
         AND report_citation.source_citation_id = finding_citation.citation_id
        WHERE report_finding.report_id = target_report_id
          AND report_citation.id IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM report_findings report_finding
        WHERE report_finding.report_id = target_report_id
          AND report_finding.validation_status_snapshot = 'VALIDATED'
          AND NOT EXISTS (
              SELECT 1 FROM report_finding_citations report_citation
              WHERE report_citation.report_finding_id = report_finding.id
          )
    );
$$;

CREATE FUNCTION generate_compliance_report(
    target_organization_id uuid,
    target_check_id uuid,
    target_generated_by uuid,
    target_report_code text,
    target_title text,
    target_executive_summary text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    check_record compliance_checks%ROWTYPE;
    new_report_id uuid;
    parent_report_id_value uuid;
    report_version integer := 1;
BEGIN
    IF NOT user_has_organization_permission(target_organization_id, target_generated_by, 'REPORT_SUBMIT') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'user lacks report submission permission';
    END IF;
    SELECT * INTO check_record FROM compliance_checks
    WHERE organization_id = target_organization_id AND id = target_check_id
    FOR SHARE;
    IF NOT FOUND OR check_record.status <> 'COMPLETED' OR check_record.overall_result IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'report generation requires a completed check with an overall result';
    END IF;
    IF EXISTS (
        SELECT 1 FROM findings finding_record
        WHERE finding_record.check_id = target_check_id
          AND finding_record.validation_status = 'VALIDATED'
          AND NOT EXISTS (
              SELECT 1 FROM finding_citations citation_link
              WHERE citation_link.finding_id = finding_record.id
          )
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'cannot generate report from a validated finding without citation';
    END IF;

    IF check_record.parent_check_id IS NOT NULL THEN
        SELECT id, version_number INTO parent_report_id_value, report_version
        FROM compliance_reports
        WHERE organization_id = target_organization_id
          AND batch_id = check_record.batch_id
          AND check_id = check_record.parent_check_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 're-check report requires the parent check report';
        END IF;
        report_version := report_version + 1;
    END IF;

    INSERT INTO compliance_reports(
        organization_id, check_id, batch_id, parent_report_id, version_number,
        report_code, overall_result, title, executive_summary, generated_by
    ) VALUES (
        target_organization_id, target_check_id, check_record.batch_id,
        parent_report_id_value, report_version, target_report_code,
        check_record.overall_result, target_title, target_executive_summary,
        target_generated_by
    ) RETURNING id INTO new_report_id;

    INSERT INTO report_findings(
        organization_id, check_id, report_id, finding_id, display_order,
        source_type_snapshot, finding_type_snapshot, title_snapshot,
        description_snapshot, severity_snapshot, validation_status_snapshot,
        actual_value_snapshot, expected_value_snapshot, unit_snapshot,
        remediation_snapshot
    )
    SELECT finding_record.organization_id, finding_record.check_id, new_report_id,
           finding_record.id,
           row_number() OVER (ORDER BY finding_record.created_at, finding_record.id) - 1,
           finding_record.source_type, finding_record.finding_type, finding_record.title,
           finding_record.description, finding_record.severity,
           finding_record.validation_status, finding_record.actual_value,
           finding_record.expected_value, finding_record.unit_text,
           finding_record.remediation_hint
    FROM findings finding_record
    WHERE finding_record.organization_id = target_organization_id
      AND finding_record.check_id = target_check_id;

    INSERT INTO report_finding_citations(
        organization_id, report_finding_id, source_citation_id, is_primary,
        citation_code_snapshot, display_label_snapshot, quote_excerpt_snapshot,
        canonical_reference_snapshot, legal_document_id,
        legal_document_version_id, legal_section_id, legal_requirement_id,
        legal_version_content_hash_snapshot, source_file_checksum_snapshot
    )
    SELECT report_finding.organization_id, report_finding.id, citation.id,
           finding_citation.is_primary, citation.citation_code,
           citation.display_label, citation.quote_excerpt,
           citation.canonical_reference, version_record.legal_document_id,
           version_record.id, section_record.id, citation.requirement_id,
           version_record.content_hash, file_snapshot.checksum
    FROM report_findings report_finding
    JOIN finding_citations finding_citation
      ON finding_citation.finding_id = report_finding.finding_id
    JOIN legal_citations citation ON citation.id = finding_citation.citation_id
    JOIN legal_sections section_record
      ON section_record.id = citation.section_id
     AND section_record.version_id = citation.version_id
    JOIN legal_document_versions version_record ON version_record.id = section_record.version_id
    LEFT JOIN LATERAL (
        SELECT CASE WHEN count(DISTINCT legal_file.checksum_sha256) = 1
                    THEN min(legal_file.checksum_sha256) END AS checksum
        FROM legal_document_files legal_file
        WHERE legal_file.version_id = version_record.id AND legal_file.is_original
    ) file_snapshot ON true
    WHERE report_finding.report_id = new_report_id;

    IF NOT report_snapshot_is_complete(new_report_id) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'generated report snapshot is incomplete';
    END IF;
    RETURN new_report_id;
END;
$$;

CREATE FUNCTION submit_compliance_report(
    target_organization_id uuid,
    target_report_id uuid,
    target_actor_id uuid
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    next_round integer;
BEGIN
    IF NOT user_has_organization_permission(target_organization_id, target_actor_id, 'REPORT_SUBMIT') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'user lacks report submission permission';
    END IF;
    IF NOT report_snapshot_is_complete(target_report_id) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'report snapshot is incomplete';
    END IF;
    UPDATE compliance_reports
    SET status = 'PENDING_APPROVAL',
        submission_round = submission_round + 1,
        submitted_at = clock_timestamp(),
        approved_at = NULL,
        approved_by = NULL,
        updated_at = clock_timestamp()
    WHERE organization_id = target_organization_id
      AND id = target_report_id
      AND status = 'DRAFT'
    RETURNING submission_round INTO next_round;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'only a draft report can be submitted';
    END IF;
    RETURN next_round;
END;
$$;

CREATE FUNCTION decide_compliance_report(
    target_organization_id uuid,
    target_report_id uuid,
    target_reviewer_id uuid,
    target_decision text,
    target_comment text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    current_round integer;
BEGIN
    IF target_decision NOT IN ('APPROVED', 'REJECTED') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid report decision';
    END IF;
    SELECT submission_round INTO current_round FROM compliance_reports
    WHERE organization_id = target_organization_id
      AND id = target_report_id
      AND status = 'PENDING_APPROVAL'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'report is not pending approval';
    END IF;
    INSERT INTO report_approvals(
        organization_id, report_id, submission_round, reviewer_id, decision, comment
    ) VALUES (
        target_organization_id, target_report_id, current_round,
        target_reviewer_id, target_decision, target_comment
    );
    IF target_decision = 'APPROVED' THEN
        UPDATE compliance_reports
        SET status = 'APPROVED', approved_at = clock_timestamp(),
            approved_by = target_reviewer_id, updated_at = clock_timestamp()
        WHERE id = target_report_id;
    ELSE
        UPDATE compliance_reports
        SET status = 'REJECTED', approved_at = NULL, approved_by = NULL,
            updated_at = clock_timestamp()
        WHERE id = target_report_id;
    END IF;
    RETURN target_decision;
END;
$$;

CREATE FUNCTION return_rejected_report_to_draft(
    target_organization_id uuid,
    target_report_id uuid,
    target_actor_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT user_has_organization_permission(target_organization_id, target_actor_id, 'REPORT_SUBMIT') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'user lacks report submission permission';
    END IF;
    UPDATE compliance_reports
    SET status = 'DRAFT', submitted_at = NULL, approved_at = NULL,
        approved_by = NULL, updated_at = clock_timestamp()
    WHERE organization_id = target_organization_id
      AND id = target_report_id
      AND status = 'REJECTED';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'only a rejected report can return to draft';
    END IF;
END;
$$;

CREATE TABLE remediation_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    report_id uuid NOT NULL,
    finding_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    priority text NOT NULL CHECK (priority IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    status text NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'IN_PROGRESS', 'EVIDENCE_SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'CANCELLED')),
    due_date date,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, report_id, id),
    FOREIGN KEY (organization_id, batch_id, report_id)
        REFERENCES compliance_reports(organization_id, batch_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, report_id, finding_id)
        REFERENCES report_findings(organization_id, report_id, finding_id) ON DELETE RESTRICT,
    CHECK (length(btrim(title)) > 0),
    CHECK (description IS NULL OR length(btrim(description)) > 0),
    CHECK ((status IN ('APPROVED', 'CANCELLED')) = (completed_at IS NOT NULL))
);

CREATE TABLE remediation_task_assignees (
    organization_id uuid NOT NULL,
    task_id uuid NOT NULL,
    user_id uuid NOT NULL,
    assigned_by uuid NOT NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, task_id, user_id),
    FOREIGN KEY (organization_id, task_id)
        REFERENCES remediation_tasks(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, user_id)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, assigned_by)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT
);

CREATE TABLE remediation_evidence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    task_id uuid NOT NULL,
    document_id uuid NOT NULL,
    document_revision_id uuid NOT NULL,
    verification_id uuid NOT NULL,
    submitted_by uuid NOT NULL,
    description text,
    status text NOT NULL DEFAULT 'SUBMITTED'
        CHECK (status IN ('SUBMITTED', 'ACCEPTED', 'REJECTED')),
    submitted_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, task_id)
        REFERENCES remediation_tasks(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, document_id)
        REFERENCES documents(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, document_id, document_revision_id)
        REFERENCES document_revisions(organization_id, document_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, document_revision_id, verification_id)
        REFERENCES document_verifications(organization_id, document_revision_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, submitted_by)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT,
    CHECK (description IS NULL OR length(btrim(description)) > 0)
);

CREATE TABLE remediation_reviews (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    task_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    decision text NOT NULL CHECK (decision IN ('APPROVED', 'REJECTED', 'CHANGES_REQUESTED')),
    comment text,
    reviewed_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, task_id)
        REFERENCES remediation_tasks(organization_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (organization_id, reviewer_id)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT,
    CHECK (comment IS NULL OR length(btrim(comment)) > 0)
);

CREATE TABLE remediation_task_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    task_id uuid NOT NULL,
    event_type text NOT NULL,
    from_status text,
    to_status text,
    actor_user_id uuid,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (organization_id, task_id)
        REFERENCES remediation_tasks(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, actor_user_id)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT,
    CHECK (length(btrim(event_type)) > 0),
    CHECK (from_status IS NULL OR from_status IN ('OPEN', 'IN_PROGRESS', 'EVIDENCE_SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'CANCELLED')),
    CHECK (to_status IS NULL OR to_status IN ('OPEN', 'IN_PROGRESS', 'EVIDENCE_SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'CANCELLED')),
    CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object')
);

CREATE FUNCTION validate_remediation_task()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    report_status text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT status INTO report_status FROM compliance_reports
        WHERE organization_id = NEW.organization_id
          AND batch_id = NEW.batch_id
          AND id = NEW.report_id;
        IF report_status <> 'APPROVED' THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'remediation tasks require an approved report';
        END IF;
        IF NEW.status <> 'OPEN' OR NOT user_has_organization_permission(
            NEW.organization_id, NEW.created_by, 'REMEDIATION_CREATE'
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'task creator lacks permission or task is not open';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD.status IN ('APPROVED', 'CANCELLED') THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal remediation tasks are immutable';
        END IF;
        RETURN OLD;
    END IF;
    IF OLD.status IN ('APPROVED', 'CANCELLED') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal remediation tasks are immutable';
    END IF;
    IF (NEW.organization_id, NEW.batch_id, NEW.report_id, NEW.finding_id,
        NEW.created_by, NEW.created_at)
       IS DISTINCT FROM
       (OLD.organization_id, OLD.batch_id, OLD.report_id, OLD.finding_id,
        OLD.created_by, OLD.created_at) THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'remediation task provenance is immutable';
    END IF;
    IF NEW.status <> OLD.status AND NOT (
        (OLD.status = 'OPEN' AND NEW.status IN ('IN_PROGRESS', 'CANCELLED'))
        OR (OLD.status = 'IN_PROGRESS' AND NEW.status IN ('EVIDENCE_SUBMITTED', 'CANCELLED'))
        OR (OLD.status = 'EVIDENCE_SUBMITTED' AND NEW.status IN ('UNDER_REVIEW', 'REJECTED'))
        OR (OLD.status = 'UNDER_REVIEW' AND NEW.status IN ('APPROVED', 'REJECTED'))
        OR (OLD.status = 'REJECTED' AND NEW.status IN ('IN_PROGRESS', 'EVIDENCE_SUBMITTED', 'CANCELLED'))
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid remediation task status transition';
    END IF;
    IF NEW.status = 'APPROVED' AND (
        NOT EXISTS (
            SELECT 1 FROM remediation_evidence evidence
            WHERE evidence.organization_id = NEW.organization_id
              AND evidence.task_id = NEW.id
              AND evidence.status = 'ACCEPTED'
        ) OR NOT EXISTS (
            SELECT 1 FROM remediation_reviews review
            WHERE review.organization_id = NEW.organization_id
              AND review.task_id = NEW.id
              AND review.decision = 'APPROVED'
        )
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'approved task requires accepted verified evidence and an approval review';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_remediation_task
BEFORE INSERT OR UPDATE OR DELETE ON remediation_tasks
FOR EACH ROW EXECUTE FUNCTION validate_remediation_task();

CREATE FUNCTION validate_remediation_assignee()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM organization_members
        WHERE organization_id = NEW.organization_id
          AND user_id = NEW.user_id
          AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'remediation assignee must be an active organization member';
    END IF;
    IF NOT user_has_organization_permission(NEW.organization_id, NEW.assigned_by, 'REMEDIATION_CREATE') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'assigner lacks remediation permission';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_remediation_assignee
BEFORE INSERT OR UPDATE ON remediation_task_assignees
FOR EACH ROW EXECUTE FUNCTION validate_remediation_assignee();

CREATE FUNCTION validate_remediation_evidence()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    revision_status text;
    verification_status text;
    task_status text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'remediation evidence history cannot be deleted';
    END IF;
    SELECT status INTO revision_status FROM document_revisions
    WHERE organization_id = NEW.organization_id
      AND document_id = NEW.document_id
      AND id = NEW.document_revision_id;
    SELECT status INTO verification_status FROM document_verifications
    WHERE organization_id = NEW.organization_id
      AND document_revision_id = NEW.document_revision_id
      AND id = NEW.verification_id;
    IF revision_status <> 'VERIFIED' OR verification_status <> 'VERIFIED' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'remediation evidence requires an exact verified revision and verification';
    END IF;
    IF TG_OP = 'INSERT' THEN
        SELECT status INTO task_status FROM remediation_tasks
        WHERE organization_id = NEW.organization_id AND id = NEW.task_id;
        IF task_status NOT IN ('IN_PROGRESS', 'REJECTED') OR NEW.status <> 'SUBMITTED' THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'new evidence must be submitted to an active remediation task';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM organization_members
            WHERE organization_id = NEW.organization_id
              AND user_id = NEW.submitted_by
              AND status = 'ACTIVE'
        ) THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'evidence submitter must be an active organization member';
        END IF;
    ELSE
        IF (NEW.organization_id, NEW.task_id, NEW.document_id, NEW.document_revision_id,
            NEW.verification_id, NEW.submitted_by, NEW.description,
            NEW.submitted_at, NEW.created_at)
           IS DISTINCT FROM
           (OLD.organization_id, OLD.task_id, OLD.document_id, OLD.document_revision_id,
            OLD.verification_id, OLD.submitted_by, OLD.description,
            OLD.submitted_at, OLD.created_at) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'remediation evidence provenance is immutable';
        END IF;
        IF OLD.status <> 'SUBMITTED' OR NEW.status NOT IN ('ACCEPTED', 'REJECTED') THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'reviewed remediation evidence is immutable';
        END IF;
        SELECT status INTO task_status FROM remediation_tasks
        WHERE organization_id = NEW.organization_id AND id = NEW.task_id;
        IF task_status <> 'EVIDENCE_SUBMITTED' THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'evidence can only be decided while its task awaits evidence review';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_remediation_evidence
BEFORE INSERT OR UPDATE OR DELETE ON remediation_evidence
FOR EACH ROW EXECUTE FUNCTION validate_remediation_evidence();

CREATE FUNCTION validate_remediation_review()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    task_status text;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'remediation review history is append-only';
    END IF;
    IF NOT user_has_organization_permission(NEW.organization_id, NEW.reviewer_id, 'REMEDIATION_REVIEW') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'reviewer lacks remediation review permission';
    END IF;
    SELECT status INTO task_status FROM remediation_tasks
    WHERE organization_id = NEW.organization_id AND id = NEW.task_id;
    IF task_status <> 'UNDER_REVIEW' OR NOT EXISTS (
        SELECT 1 FROM remediation_evidence evidence
        WHERE evidence.organization_id = NEW.organization_id
          AND evidence.task_id = NEW.task_id
          AND evidence.status = 'ACCEPTED'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'task review requires accepted verified evidence under review';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_remediation_review
BEFORE INSERT OR UPDATE OR DELETE ON remediation_reviews
FOR EACH ROW EXECUTE FUNCTION validate_remediation_review();

CREATE FUNCTION protect_remediation_task_events()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'remediation task events are append-only';
END;
$$;

CREATE TRIGGER trg_protect_remediation_task_events
BEFORE UPDATE OR DELETE ON remediation_task_events
FOR EACH ROW EXECUTE FUNCTION protect_remediation_task_events();

CREATE FUNCTION create_remediation_task(
    target_organization_id uuid,
    target_report_id uuid,
    target_finding_id uuid,
    target_title text,
    target_description text,
    target_priority text,
    target_due_date date,
    target_created_by uuid
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    target_batch_id uuid;
    new_task_id uuid;
BEGIN
    SELECT batch_id INTO target_batch_id FROM compliance_reports
    WHERE organization_id = target_organization_id AND id = target_report_id;
    INSERT INTO remediation_tasks(
        organization_id, batch_id, report_id, finding_id, title,
        description, priority, due_date, created_by
    ) VALUES (
        target_organization_id, target_batch_id, target_report_id,
        target_finding_id, target_title, target_description,
        target_priority, target_due_date, target_created_by
    ) RETURNING id INTO new_task_id;
    INSERT INTO remediation_task_events(
        organization_id, task_id, event_type, to_status, actor_user_id
    ) VALUES (target_organization_id, new_task_id, 'TASK_CREATED', 'OPEN', target_created_by);
    RETURN new_task_id;
END;
$$;

CREATE FUNCTION assign_remediation_task(
    target_organization_id uuid,
    target_task_id uuid,
    target_user_id uuid,
    target_assigned_by uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO remediation_task_assignees(organization_id, task_id, user_id, assigned_by)
    VALUES (target_organization_id, target_task_id, target_user_id, target_assigned_by);
    INSERT INTO remediation_task_events(
        organization_id, task_id, event_type, actor_user_id, metadata
    ) VALUES (
        target_organization_id, target_task_id, 'ASSIGNEE_ADDED', target_assigned_by,
        jsonb_build_object('user_id', target_user_id)
    );
END;
$$;

CREATE FUNCTION start_remediation_task(
    target_organization_id uuid,
    target_task_id uuid,
    target_actor_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE remediation_tasks SET status = 'IN_PROGRESS', updated_at = clock_timestamp()
    WHERE organization_id = target_organization_id AND id = target_task_id AND status = 'OPEN';
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'only an open remediation task can start';
    END IF;
    INSERT INTO remediation_task_events(
        organization_id, task_id, event_type, from_status, to_status, actor_user_id
    ) VALUES (
        target_organization_id, target_task_id, 'TASK_STARTED', 'OPEN', 'IN_PROGRESS', target_actor_id
    );
END;
$$;

CREATE FUNCTION submit_remediation_evidence(
    target_organization_id uuid,
    target_task_id uuid,
    target_document_id uuid,
    target_revision_id uuid,
    target_verification_id uuid,
    target_submitted_by uuid,
    target_description text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    old_task_status text;
    new_evidence_id uuid;
BEGIN
    SELECT status INTO old_task_status FROM remediation_tasks
    WHERE organization_id = target_organization_id AND id = target_task_id FOR UPDATE;
    INSERT INTO remediation_evidence(
        organization_id, task_id, document_id, document_revision_id,
        verification_id, submitted_by, description
    ) VALUES (
        target_organization_id, target_task_id, target_document_id,
        target_revision_id, target_verification_id, target_submitted_by,
        target_description
    ) RETURNING id INTO new_evidence_id;
    UPDATE remediation_tasks
    SET status = 'EVIDENCE_SUBMITTED', updated_at = clock_timestamp()
    WHERE organization_id = target_organization_id AND id = target_task_id;
    INSERT INTO remediation_task_events(
        organization_id, task_id, event_type, from_status, to_status,
        actor_user_id, metadata
    ) VALUES (
        target_organization_id, target_task_id, 'EVIDENCE_SUBMITTED',
        old_task_status, 'EVIDENCE_SUBMITTED', target_submitted_by,
        jsonb_build_object('evidence_id', new_evidence_id)
    );
    RETURN new_evidence_id;
END;
$$;

CREATE FUNCTION decide_remediation_evidence(
    target_organization_id uuid,
    target_evidence_id uuid,
    target_reviewer_id uuid,
    target_decision text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    target_task_id uuid;
    next_task_status text;
    event_name text;
BEGIN
    IF target_decision NOT IN ('ACCEPTED', 'REJECTED') THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid evidence decision';
    END IF;
    IF NOT user_has_organization_permission(target_organization_id, target_reviewer_id, 'REMEDIATION_REVIEW') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'reviewer lacks remediation review permission';
    END IF;
    UPDATE remediation_evidence
    SET status = target_decision
    WHERE organization_id = target_organization_id
      AND id = target_evidence_id
      AND status = 'SUBMITTED'
    RETURNING task_id INTO target_task_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'evidence is not pending review';
    END IF;
    next_task_status := CASE WHEN target_decision = 'ACCEPTED' THEN 'UNDER_REVIEW' ELSE 'REJECTED' END;
    event_name := CASE WHEN target_decision = 'ACCEPTED' THEN 'EVIDENCE_ACCEPTED' ELSE 'EVIDENCE_REJECTED' END;
    UPDATE remediation_tasks
    SET status = next_task_status, updated_at = clock_timestamp()
    WHERE organization_id = target_organization_id
      AND id = target_task_id
      AND status = 'EVIDENCE_SUBMITTED';
    INSERT INTO remediation_task_events(
        organization_id, task_id, event_type, from_status, to_status,
        actor_user_id, metadata
    ) VALUES (
        target_organization_id, target_task_id, event_name,
        'EVIDENCE_SUBMITTED', next_task_status, target_reviewer_id,
        jsonb_build_object('evidence_id', target_evidence_id)
    );
END;
$$;

CREATE FUNCTION review_remediation_task(
    target_organization_id uuid,
    target_task_id uuid,
    target_reviewer_id uuid,
    target_decision text,
    target_comment text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    new_review_id uuid;
    next_task_status text;
    event_name text;
BEGIN
    INSERT INTO remediation_reviews(
        organization_id, task_id, reviewer_id, decision, comment
    ) VALUES (
        target_organization_id, target_task_id, target_reviewer_id,
        target_decision, target_comment
    ) RETURNING id INTO new_review_id;
    next_task_status := CASE WHEN target_decision = 'APPROVED' THEN 'APPROVED' ELSE 'REJECTED' END;
    event_name := CASE WHEN target_decision = 'APPROVED' THEN 'REVIEW_APPROVED' ELSE 'REVIEW_REJECTED' END;
    UPDATE remediation_tasks
    SET status = next_task_status,
        completed_at = CASE WHEN next_task_status = 'APPROVED' THEN clock_timestamp() ELSE NULL END,
        updated_at = clock_timestamp()
    WHERE organization_id = target_organization_id
      AND id = target_task_id
      AND status = 'UNDER_REVIEW';
    INSERT INTO remediation_task_events(
        organization_id, task_id, event_type, from_status, to_status,
        actor_user_id, metadata
    ) VALUES (
        target_organization_id, target_task_id, event_name,
        'UNDER_REVIEW', next_task_status, target_reviewer_id,
        jsonb_build_object('review_id', new_review_id, 'decision', target_decision)
    );
    RETURN new_review_id;
END;
$$;

CREATE FUNCTION create_recheck_for_report(
    target_organization_id uuid,
    target_report_id uuid,
    target_created_by uuid,
    target_idempotency_key text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    source_report record;
    next_check_number integer;
    new_check_id uuid;
BEGIN
    IF target_idempotency_key IS NULL OR length(btrim(target_idempotency_key)) = 0 THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 're-check requires a non-empty idempotency key';
    END IF;
    IF NOT user_has_organization_permission(target_organization_id, target_created_by, 'COMPLIANCE_RECHECK') THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'user lacks compliance re-check permission';
    END IF;
    SELECT report_record.check_id, report_record.batch_id, report_record.status,
           check_record.market_id, check_record.status AS check_status
    INTO source_report
    FROM compliance_reports report_record
    JOIN compliance_checks check_record
      ON check_record.organization_id = report_record.organization_id
     AND check_record.id = report_record.check_id
    WHERE report_record.organization_id = target_organization_id
      AND report_record.id = target_report_id
    FOR SHARE;
    IF NOT FOUND OR source_report.status <> 'APPROVED' OR source_report.check_status <> 'COMPLETED' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 're-check requires an approved report from a completed check';
    END IF;
    IF EXISTS (
        SELECT 1 FROM remediation_tasks task_record
        WHERE task_record.organization_id = target_organization_id
          AND task_record.report_id = target_report_id
          AND task_record.status <> 'APPROVED'
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'unresolved remediation tasks block re-check';
    END IF;
    IF EXISTS (
        SELECT 1 FROM remediation_tasks task_record
        WHERE task_record.organization_id = target_organization_id
          AND task_record.report_id = target_report_id
          AND NOT EXISTS (
              SELECT 1 FROM remediation_evidence evidence
              WHERE evidence.organization_id = task_record.organization_id
                AND evidence.task_id = task_record.id
                AND evidence.status = 'ACCEPTED'
          )
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 're-check requires accepted verified remediation evidence';
    END IF;

    PERFORM 1 FROM export_batches
    WHERE organization_id = target_organization_id AND id = source_report.batch_id
    FOR UPDATE;
    SELECT coalesce(max(check_number), 0) + 1 INTO next_check_number
    FROM compliance_checks
    WHERE organization_id = target_organization_id AND batch_id = source_report.batch_id;
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, parent_check_id,
        check_number, status, idempotency_key
    ) VALUES (
        target_organization_id, source_report.batch_id, source_report.market_id,
        target_created_by, source_report.check_id, next_check_number,
        'QUEUED', target_idempotency_key
    ) RETURNING id INTO new_check_id;

    INSERT INTO remediation_task_events(
        organization_id, task_id, event_type, actor_user_id, metadata
    )
    SELECT target_organization_id, task_record.id, 'RECHECK_CREATED',
           target_created_by, jsonb_build_object('check_id', new_check_id)
    FROM remediation_tasks task_record
    WHERE task_record.organization_id = target_organization_id
      AND task_record.report_id = target_report_id;
    RETURN new_check_id;
END;
$$;

CREATE INDEX idx_compliance_reports_batch_version
    ON compliance_reports(organization_id, batch_id, version_number DESC);
CREATE INDEX idx_compliance_reports_status
    ON compliance_reports(organization_id, status, created_at);
CREATE INDEX idx_report_findings_report_order
    ON report_findings(organization_id, report_id, display_order);
CREATE INDEX idx_report_citations_source
    ON report_finding_citations(source_citation_id);
CREATE INDEX idx_report_approvals_report_round
    ON report_approvals(organization_id, report_id, submission_round);
CREATE INDEX idx_remediation_tasks_report_status
    ON remediation_tasks(organization_id, report_id, status);
CREATE INDEX idx_remediation_tasks_batch_status
    ON remediation_tasks(organization_id, batch_id, status);
CREATE INDEX idx_remediation_evidence_task
    ON remediation_evidence(organization_id, task_id, submitted_at);
CREATE INDEX idx_remediation_reviews_task
    ON remediation_reviews(organization_id, task_id, reviewed_at);
CREATE INDEX idx_remediation_events_task_created
    ON remediation_task_events(organization_id, task_id, created_at);
