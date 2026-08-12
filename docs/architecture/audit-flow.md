# Audit and Worker Flow

## Business audit

An audit event is part of the same transaction as the critical mutation:

```text
authenticated request
  -> BEGIN
  -> SET LOCAL user + organization context
  -> RBAC/domain validation
  -> business mutation
  -> record_audit_event(...)
  -> optional record_audit_log_change(...) rows
  -> COMMIT
```

If either the mutation or audit insert fails, the transaction rolls back both. `AuditService` is intentionally a thin adapter: callers must pass the same transaction-scoped database client used for the business operation. Phase 10 does not refactor every prior workflow into a new API layer.

`audit_logs` records the event, actor, tenant, result, request/trace/network context, source, and small metadata. `audit_log_changes` records only material field changes; it avoids copying entire before/after records. Authentication events use category `AUTH`; there is no duplicate authentication-audit table.

Application audit writes go through `record_audit_event`, which requires matching user context, active membership for tenant events, and source `USER` or `API`. Worker/system events use a separately granted function.

## Sensitive data access

`data_access_logs` records deliberate access to sensitive resources such as document files, compliance reports, and legal-evidence exports. It is intended for VIEW, DOWNLOAD, EXPORT, or PRINT events that matter for security review—not ordinary dashboard reads.

`DataAccessAuditService` uses `record_data_access`, which verifies both the active tenant context and that the actor equals the authenticated user context.

## Append-only history

`audit_logs`, `audit_log_changes`, and `data_access_logs` reject UPDATE and DELETE through triggers even for the schema owner. Application roles also have no direct write privileges. Corrections are new audit events; prior history is never rewritten.

## Worker jobs

`system_job_runs` is the generic execution ledger for OCR, AI, embedding, legal-impact scans, notification delivery, and future workers. A job begins `QUEUED`, uses tenant/global idempotency indexes, and follows an explicit lifecycle:

```text
QUEUED -> RUNNING -> COMPLETED
                  -> FAILED -> QUEUED (attempt + 1)
                  -> CANCELLED
```

Counts cannot be negative or exceed processed items, retries are bounded, identity fields are immutable, and completed/cancelled history cannot be changed or deleted. The worker role is explicit and has no general tenant-table RLS bypass.
