CREATE TABLE document_types (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL UNIQUE,
    name_vi text NOT NULL,
    name_en text NOT NULL,
    requires_ocr boolean NOT NULL DEFAULT false,
    requires_verification boolean NOT NULL DEFAULT true,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (code = upper(code)),
    CHECK (length(btrim(code)) > 0)
);

CREATE TABLE documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    document_type_id uuid NOT NULL REFERENCES document_types(id) ON DELETE RESTRICT,
    document_number text,
    title text,
    issue_date date,
    expiry_date date,
    issuing_organization text,
    status text NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'SUPERSEDED', 'ARCHIVED')),
    supersedes_document_id uuid,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, supersedes_document_id)
        REFERENCES documents(organization_id, id) ON DELETE RESTRICT,
    CHECK (document_number IS NULL OR length(btrim(document_number)) > 0),
    CHECK (title IS NULL OR length(btrim(title)) > 0),
    CHECK (expiry_date IS NULL OR issue_date IS NULL OR expiry_date >= issue_date),
    CHECK (supersedes_document_id IS NULL OR supersedes_document_id <> id),
    CHECK (deleted_at IS NULL OR deleted_at >= created_at)
);

CREATE TABLE document_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    document_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    previous_revision_id uuid,
    status text NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT', 'READY_FOR_REVIEW', 'VERIFIED', 'REJECTED', 'SUPERSEDED')),
    content_checksum text,
    created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    verified_at timestamptz,
    superseded_at timestamptz,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, document_id, id),
    UNIQUE (organization_id, document_id, revision_number),
    FOREIGN KEY (organization_id, document_id)
        REFERENCES documents(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, document_id, previous_revision_id)
        REFERENCES document_revisions(organization_id, document_id, id) ON DELETE RESTRICT,
    CHECK (previous_revision_id IS NULL OR previous_revision_id <> id),
    CHECK (content_checksum IS NULL OR content_checksum ~ '^[0-9a-fA-F]{64}$'),
    CHECK ((status IN ('VERIFIED', 'SUPERSEDED')) = (verified_at IS NOT NULL)),
    CHECK ((status = 'SUPERSEDED') = (superseded_at IS NOT NULL)),
    CHECK (verified_at IS NULL OR verified_at >= created_at),
    CHECK (superseded_at IS NULL OR superseded_at >= verified_at)
);

CREATE TABLE document_files (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    document_revision_id uuid NOT NULL,
    storage_provider text NOT NULL,
    bucket_name text NOT NULL,
    storage_path text NOT NULL,
    original_file_name text NOT NULL,
    mime_type text NOT NULL,
    file_size_bytes bigint NOT NULL CHECK (file_size_bytes >= 0),
    checksum_sha256 text,
    page_count integer CHECK (page_count IS NULL OR page_count > 0),
    uploaded_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    uploaded_at timestamptz NOT NULL DEFAULT now(),
    is_original boolean NOT NULL DEFAULT true,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, document_revision_id)
        REFERENCES document_revisions(organization_id, id) ON DELETE CASCADE,
    CHECK (length(btrim(storage_provider)) > 0),
    CHECK (length(btrim(bucket_name)) > 0),
    CHECK (length(btrim(storage_path)) > 0),
    CHECK (storage_path !~* '^https?://'),
    CHECK (length(btrim(original_file_name)) > 0),
    CHECK (length(btrim(mime_type)) > 0),
    CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-fA-F]{64}$'),
    CHECK (NOT is_original OR checksum_sha256 IS NOT NULL)
);

CREATE TABLE batch_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    document_id uuid NOT NULL,
    purpose text,
    is_required boolean NOT NULL DEFAULT false,
    attached_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    attached_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (organization_id, batch_id)
        REFERENCES export_batches(organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, document_id)
        REFERENCES documents(organization_id, id) ON DELETE CASCADE,
    UNIQUE (organization_id, batch_id, document_id),
    CHECK (purpose IS NULL OR length(btrim(purpose)) > 0)
);

CREATE FUNCTION protect_verified_document_revision()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status IN ('VERIFIED', 'SUPERSEDED') THEN
            RAISE EXCEPTION USING
                ERRCODE = '55000',
                MESSAGE = 'verified or superseded document revisions are immutable';
        END IF;
        RETURN OLD;
    END IF;

    IF NEW.status = 'SUPERSEDED' AND OLD.status <> 'VERIFIED' THEN
        RAISE EXCEPTION USING
            ERRCODE = '55000',
            MESSAGE = 'only a verified document revision can be superseded';
    END IF;

    IF OLD.status IN ('VERIFIED', 'SUPERSEDED') THEN
        IF (NEW.organization_id, NEW.document_id, NEW.revision_number,
            NEW.previous_revision_id, NEW.content_checksum, NEW.created_by,
            NEW.created_at, NEW.verified_at)
           IS DISTINCT FROM
           (OLD.organization_id, OLD.document_id, OLD.revision_number,
            OLD.previous_revision_id, OLD.content_checksum, OLD.created_by,
            OLD.created_at, OLD.verified_at) THEN
            RAISE EXCEPTION USING
                ERRCODE = '55000',
                MESSAGE = 'verified or superseded document revision content is immutable';
        END IF;

        IF OLD.status = 'VERIFIED' AND NEW.status = 'SUPERSEDED' THEN
            RETURN NEW;
        END IF;

        IF NEW.status <> OLD.status OR NEW.superseded_at IS DISTINCT FROM OLD.superseded_at THEN
            RAISE EXCEPTION USING
                ERRCODE = '55000',
                MESSAGE = 'invalid state change for immutable document revision';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_verified_document_revision
BEFORE UPDATE OR DELETE ON document_revisions
FOR EACH ROW EXECUTE FUNCTION protect_verified_document_revision();

CREATE FUNCTION protect_verified_revision_files()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    revision_is_protected boolean;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT status IN ('VERIFIED', 'SUPERSEDED')
        INTO revision_is_protected
        FROM document_revisions
        WHERE organization_id = OLD.organization_id
          AND id = OLD.document_revision_id;

        IF coalesce(revision_is_protected, false) THEN
            RAISE EXCEPTION USING
                ERRCODE = '55000',
                MESSAGE = 'files of a verified or superseded revision are immutable';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT status IN ('VERIFIED', 'SUPERSEDED')
        INTO revision_is_protected
        FROM document_revisions
        WHERE organization_id = NEW.organization_id
          AND id = NEW.document_revision_id;

        IF coalesce(revision_is_protected, false) THEN
            RAISE EXCEPTION USING
                ERRCODE = '55000',
                MESSAGE = 'file membership of a verified or superseded revision is immutable';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_verified_revision_files
BEFORE INSERT OR UPDATE OR DELETE ON document_files
FOR EACH ROW EXECUTE FUNCTION protect_verified_revision_files();

CREATE INDEX idx_documents_organization_type
    ON documents(organization_id, document_type_id);
CREATE INDEX idx_documents_organization_number
    ON documents(organization_id, document_number);
CREATE INDEX idx_documents_organization_status
    ON documents(organization_id, status);
CREATE INDEX idx_document_revisions_organization_status
    ON document_revisions(organization_id, status);
CREATE INDEX idx_document_files_organization_revision
    ON document_files(organization_id, document_revision_id);
CREATE INDEX idx_batch_documents_organization_document
    ON batch_documents(organization_id, document_id);

