CREATE TABLE audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid REFERENCES organizations(id) ON DELETE RESTRICT,
    user_id uuid REFERENCES users(id) ON DELETE RESTRICT,
    category text NOT NULL CHECK (category IN (
        'AUTH', 'ORGANIZATION', 'BATCH', 'DOCUMENT', 'LEGAL', 'COMPLIANCE',
        'REPORT', 'REMEDIATION', 'MONITORING', 'SECURITY', 'SYSTEM'
    )),
    action text NOT NULL,
    entity_type text,
    entity_id uuid,
    result text NOT NULL CHECK (result IN ('SUCCESS', 'FAILURE', 'DENIED')),
    request_id uuid,
    trace_id text,
    ip_address inet,
    user_agent text,
    source text NOT NULL CHECK (source IN (
        'USER', 'API', 'WORKER', 'RULE_ENGINE', 'AI', 'SYSTEM', 'SYSTEM_ADMIN'
    )),
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    CHECK (action ~ '^[A-Z][A-Z0-9_]*$'),
    CHECK ((entity_type IS NULL) = (entity_id IS NULL)),
    CHECK (entity_type IS NULL OR length(btrim(entity_type)) > 0),
    CHECK (trace_id IS NULL OR length(btrim(trace_id)) > 0),
    CHECK (user_agent IS NULL OR length(btrim(user_agent)) > 0),
    CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object')
);

CREATE TABLE audit_log_changes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    audit_log_id uuid NOT NULL REFERENCES audit_logs(id) ON DELETE RESTRICT,
    field_name text NOT NULL,
    old_value jsonb,
    new_value jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (length(btrim(field_name)) > 0),
    CHECK (old_value IS DISTINCT FROM new_value)
);

CREATE TABLE data_access_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    resource_type text NOT NULL,
    resource_id uuid NOT NULL,
    access_type text NOT NULL CHECK (access_type IN ('VIEW', 'DOWNLOAD', 'EXPORT', 'PRINT')),
    request_id uuid,
    ip_address inet,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, user_id)
        REFERENCES organization_members(organization_id, user_id) ON DELETE RESTRICT,
    CHECK (resource_type ~ '^[A-Z][A-Z0-9_]*$')
);

CREATE TABLE system_job_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    job_type text NOT NULL,
    job_key text,
    organization_id uuid REFERENCES organizations(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'QUEUED'
        CHECK (status IN ('QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    idempotency_key text,
    attempt_number integer NOT NULL DEFAULT 1,
    max_attempts integer NOT NULL DEFAULT 3,
    next_retry_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    items_processed integer NOT NULL DEFAULT 0,
    items_succeeded integer NOT NULL DEFAULT 0,
    items_failed integer NOT NULL DEFAULT 0,
    last_error_code text,
    error_message text,
    metadata jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, id),
    CHECK (job_type ~ '^[A-Z][A-Z0-9_]*$'),
    CHECK (job_key IS NULL OR length(btrim(job_key)) > 0),
    CHECK (idempotency_key IS NULL OR length(btrim(idempotency_key)) > 0),
    CHECK (attempt_number >= 1 AND max_attempts >= 1 AND attempt_number <= max_attempts),
    CHECK (items_processed >= 0 AND items_succeeded >= 0 AND items_failed >= 0),
    CHECK (items_succeeded + items_failed <= items_processed),
    CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    CHECK (
        (status = 'QUEUED' AND started_at IS NULL AND completed_at IS NULL)
        OR (status = 'RUNNING' AND started_at IS NOT NULL AND completed_at IS NULL)
        OR (status IN ('COMPLETED', 'FAILED', 'CANCELLED') AND completed_at IS NOT NULL)
    ),
    CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE UNIQUE INDEX uq_system_job_runs_tenant_idempotency
    ON system_job_runs(organization_id, idempotency_key)
    WHERE organization_id IS NOT NULL AND idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX uq_system_job_runs_global_idempotency
    ON system_job_runs(idempotency_key)
    WHERE organization_id IS NULL AND idempotency_key IS NOT NULL;

CREATE FUNCTION protect_append_only_security_history()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '55000',
        MESSAGE = TG_TABLE_NAME || ' is append-only; record a new event instead';
END;
$$;

CREATE TRIGGER trg_protect_audit_logs_history
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION protect_append_only_security_history();
CREATE TRIGGER trg_protect_audit_log_changes_history
BEFORE UPDATE OR DELETE ON audit_log_changes
FOR EACH ROW EXECUTE FUNCTION protect_append_only_security_history();
CREATE TRIGGER trg_protect_data_access_logs_history
BEFORE UPDATE OR DELETE ON data_access_logs
FOR EACH ROW EXECUTE FUNCTION protect_append_only_security_history();

CREATE FUNCTION validate_system_job_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'system job history cannot be deleted';
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'QUEUED' THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'new system jobs must start queued';
        END IF;
        RETURN NEW;
    END IF;
    IF (NEW.id, NEW.job_type, NEW.job_key, NEW.organization_id,
        NEW.idempotency_key, NEW.max_attempts, NEW.created_at)
       IS DISTINCT FROM
       (OLD.id, OLD.job_type, OLD.job_key, OLD.organization_id,
        OLD.idempotency_key, OLD.max_attempts, OLD.created_at) THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'system job identity is immutable';
    END IF;
    IF OLD.status IN ('COMPLETED', 'CANCELLED') THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'terminal system job history is immutable';
    END IF;
    IF NEW.status <> OLD.status AND NOT (
        (OLD.status = 'QUEUED' AND NEW.status IN ('RUNNING', 'CANCELLED'))
        OR (OLD.status = 'RUNNING' AND NEW.status IN ('COMPLETED', 'FAILED', 'CANCELLED'))
        OR (OLD.status = 'FAILED' AND NEW.status = 'QUEUED'
            AND NEW.attempt_number = OLD.attempt_number + 1
            AND NEW.attempt_number <= NEW.max_attempts)
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid system job lifecycle transition';
    END IF;
    IF NEW.status = OLD.status AND NEW.attempt_number <> OLD.attempt_number THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'attempt number changes only during a failed-job retry';
    END IF;
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_system_job_lifecycle
BEFORE INSERT OR UPDATE OR DELETE ON system_job_runs
FOR EACH ROW EXECUTE FUNCTION validate_system_job_lifecycle();

CREATE INDEX idx_audit_logs_organization_created
    ON audit_logs(organization_id, created_at DESC) WHERE organization_id IS NOT NULL;
CREATE INDEX idx_audit_logs_user_created
    ON audit_logs(user_id, created_at DESC) WHERE user_id IS NOT NULL;
CREATE INDEX idx_audit_logs_entity
    ON audit_logs(entity_type, entity_id, created_at DESC) WHERE entity_id IS NOT NULL;
CREATE INDEX idx_audit_logs_request
    ON audit_logs(request_id) WHERE request_id IS NOT NULL;
CREATE INDEX idx_audit_log_changes_log
    ON audit_log_changes(audit_log_id, created_at);
CREATE INDEX idx_data_access_logs_organization_created
    ON data_access_logs(organization_id, created_at DESC);
CREATE INDEX idx_data_access_logs_resource
    ON data_access_logs(resource_type, resource_id, created_at DESC);
CREATE INDEX idx_system_job_runs_queue
    ON system_job_runs(status, next_retry_at, created_at)
    WHERE status IN ('QUEUED', 'FAILED');
CREATE INDEX idx_system_job_runs_organization
    ON system_job_runs(organization_id, created_at DESC) WHERE organization_id IS NOT NULL;

