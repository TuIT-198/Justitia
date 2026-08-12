# Implementation Status

## Current Phase

Phase 10 — System Audit, RLS, and Security Hardening. Complete and runtime-verified.

## DONE

### Phase 01–09

- PostgreSQL 15 + pgvector, identity/RBAC, reference data, products/HS, export batches, and registry linkage.
- Immutable document revisions/files, OCR/lab measurements, and human verification.
- Provenance-backed legal knowledge, deterministic compliance, citation-safe AI/RAG, immutable reports, remediation, and re-check lineage.
- Deterministic legal-version monitoring, tenant batch impacts, deduplicated alerts, recipients, and notification delivery records.

### Phase 10 — Audit, RLS, and Security

- Added append-only `audit_logs`, `audit_log_changes`, and `data_access_logs` with approved tenant-context insert functions.
- Added `system_job_runs` with tenant/global idempotency, bounded retries, explicit lifecycle, result counters, and immutable terminal history.
- Added passwordless NOLOGIN logical roles `themis_app`, `themis_worker`, and explicit `themis_admin`; the application and worker roles cannot bypass RLS or perform DDL.
- Revoked PUBLIC table/sequence/function privileges and PUBLIC schema creation; new functions no longer receive default PUBLIC execution.
- Added fail-closed UUID context helpers and active-membership enforcement using fixed-search-path, explicitly qualified security-definer helpers.
- Enabled RLS on all implemented tenant-owned tables and tenant-derived finding/audit children, with both read predicates and write checks.
- Granted the application role SELECT-only global reference/legal access and no legal-knowledge mutation privilege.
- Added minimal `AuditService`, `DataAccessAuditService`, and `SystemJobService` adapters.
- Added dedicated tests for tenant read/write isolation, active/suspended/removed membership, missing/malformed context, context switching, cross-tenant FKs, global reference privileges, append-only audit, DDL/trigger/RLS bypass attempts, search-path hijacking, and worker-job access.
- Seeded only `AUDIT_READ` and `SECURITY_AUDIT_ACCESS` permissions. No audit events, access events, job runs, or sensitive data were seeded.
- Verified all 24 migrations from an empty database, migration rerun, every reference seed rerun, Phase 01–09 database regressions, Phase 10 RLS/security assertions, and all 32 JavaScript AI/domain/monitoring/security tests.

## IN_PROGRESS

- None.

## TODO

- None within Prompt 10.
- Backend API, dashboard/frontend, PDF export, production crawling, external email/SIEM, Supabase migration, production LOGIN-role provisioning, and deployment remain deferred.

## BLOCKED

- None for Phase 10.
- Live Gemini, email, and SIEM integrations still require intentionally absent production credentials/infrastructure.

## Important Decisions

- RLS uses transaction-local `app.user_id` and `app.organization_id`; missing, empty, malformed, inactive, or mismatched context returns no tenant rows.
- The trusted backend must authenticate the request, validate membership, begin a transaction, and use `SET LOCAL`. Database credentials and context selection are never exposed to clients.
- RLS enforces tenant boundaries; RBAC/domain functions continue to enforce what an active member may do.
- Composite foreign keys remain the second tenant-integrity layer and are explicitly regression-tested under RLS.
- Security-definer helpers exist only to avoid recursive membership/parent RLS. They use fixed `pg_catalog, public` search paths, explicit `public.` references, least execution grants, and no application ownership.
- `themis_admin` is a separate NOLOGIN BYPASSRLS role. It is not granted to `themis_app` or `themis_worker`.
- Global legal/reference data is shared and SELECT-only for `themis_app`; legal writes require an explicit administrative backend path.
- Business mutation and audit insert must use the same transaction-scoped database client. A failed mutation or audit rolls back both.
- Audit correction means a new event. Audit events, field changes, and sensitive-access history cannot be updated or deleted.
- Sensitive-access logging targets document/file/report/evidence access, not ordinary dashboard reads.
- System jobs distinguish global and tenant idempotency so NULL organization values cannot create duplicate global work.
- Supabase remains a future adapter: `app_current_user_id()` can later map to trusted `auth.uid()` without rewriting tenant tables.

## Deferred Explicitly

Production auth/API orchestration, real LOGIN role/secret provisioning, Supabase migration, external SIEM/email delivery, crawling, dashboards/frontend, PDF rendering/export, production AI/embedding workers, and deployment are outside Phase 10.
