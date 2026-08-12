# Themis LexiGuard

PostgreSQL and minimal domain-service foundation for Themis LexiGuard. Implemented modules include identity/RBAC, products/HS, export batches, registries, immutable document evidence, OCR/lab verification, relational legal knowledge, deterministic compliance checks, citation-safe AI/RAG, reports/remediation/re-checks, legal monitoring, append-only audit, worker jobs, and portable tenant RLS.

## Prerequisites

- Docker Desktop with Docker Compose (the project image builds PostgreSQL 15 with pgvector 0.8.1)
- PowerShell 7 or Windows PowerShell 5.1
- Node.js 18 or newer for AI-module tests

Copy `.env.example` to `.env` and choose a local-only password. Never commit `.env`.

## Local PostgreSQL

Build and start PostgreSQL, then wait for the health check:

```powershell
docker compose up -d --build --wait postgres
```

Run all pending migrations and idempotent reference seeds:

```powershell
./scripts/migrate.ps1
```

Inspect the database:

```powershell
docker compose exec postgres psql -U themis -d themis
```

Useful commands inside `psql` include `\dt`, `\d users`, and `SELECT * FROM schema_migrations ORDER BY version;`.

Run all database tests, including migrations from an empty database, Phase 01-09 regressions, and Phase 10 RLS/security assertions, against a disposable database:

```powershell
./scripts/test-db.ps1
```

Run the dependency-free AI module tests:

```powershell
node --test tests/ai/*.test.js
```

Run report/remediation/re-check domain adapter tests:

```powershell
node --test tests/domain/*.test.js
```

Run legal-monitoring domain adapter tests:

```powershell
npm run test:monitoring
```

Run audit/job security adapter tests:

```powershell
npm run test:security
```

Reset the local database schema, then rebuild it:

```powershell
./scripts/reset-db.ps1
./scripts/migrate.ps1
```

The reset command drops the `public` schema in the selected local database. It is destructive and must not be pointed at a shared or production database.

Stop PostgreSQL while retaining data:

```powershell
docker compose down
```

## Migration policy

Migrations in `db/migrations` are applied lexicographically and recorded in `schema_migrations`. Never edit a migration after it has been applied outside local development; add a new numbered migration instead. Seed migrations use upserts and are safe to execute again. No unverified HS codes, PUC/PHC records, MRLs, legal citations, or other legal data are seeded.

## Private document storage

Document binaries belong in a private object bucket; only provider, bucket, private object path, size, MIME type, and checksum metadata belong in PostgreSQL. Configure the blank storage placeholders in `.env` only when a backend integration exists.

An authorized backend verifies tenant permission, generates a short-lived signed URL for the exact private object, and returns it to the client. Frontend clients must never hold a service-role key or generate arbitrary signed URLs. Permanent public URLs and signed URLs must not be stored in `document_files`.

## OCR and measurement boundary

Database tables model queued/retried extraction work, preserve raw provider evidence separately from normalized fields, and record reviewer corrections. No OCR SDK, fake OCR API, analyte catalog, MRL, or legal limit is included.

Numeric unit normalization is application-calculated:

```text
normalized_value = raw_value * conversion_factor + conversion_offset
```

PostgreSQL enforces that raw and normalized units share a dimension and that the normalized unit is the active canonical unit.

## Legal and deterministic compliance boundary

Legal knowledge is global/shared reference data. Production requirements, limits, citations, and approvals must trace to an exact immutable legal section/version and then to an official source. Compliance checks snapshot exact verified evidence and exact approved/active legal versions, and persist every deterministic execution including PASS.

No production legal source, authority, substance, requirement, limit, approval, rule, check, finding, threshold, citation, embedding, AI result, or compliance conclusion is seeded. Test records are transaction-scoped fixtures and are rolled back.

## RAG and compliance AI boundary

RAG chunks are derived from `legal_sections.content`; they are retrieval artifacts, never final legal citations. `retrieve_legal_chunks_for_check` filters through the exact `compliance_check_legal_versions` snapshot before scoring pgvector embeddings. Embedding dimensions are stored and validated per model instead of being hard-coded globally.

The JavaScript AI module uses one provider interface with Gemini and deterministic test implementations. Output is accepted only through an exact structured contract. Every citation ID must be present in the supplied context and valid for the tenant/check legal snapshot. Missing or invalid citations force manual review; AI never writes `compliance_checks.overall_result`.

Set Gemini and embedding placeholders only in an uncommitted `.env`. Tests do not call a real provider and do not fake production success. See `docs/ai/rag-and-compliance-ai.md` for service and failure behavior.

## Report, remediation, and re-check boundary

A completed check can generate at most one report. Generation is atomic: the report header, every finding snapshot, and every exact citation/provenance snapshot are created in one transaction. Submission uses numbered rounds; OWNER or MANAGER approval locks the complete report snapshot permanently. Rejection returns the same report to draft for a new submission round without overwriting decision history.

Remediation tasks belong to an approved report and one of its snapshotted findings. Evidence references an exact `VERIFIED` document revision and matching `VERIFIED` verification. Accepted evidence and an append-only approval review are required before a task can become `APPROVED`.

Re-checking creates a new `compliance_checks` row with same-batch `parent_check_id`, a new check number, and a new idempotency key. It does not copy old snapshots or execute deterministic/AI analysis. After separate processing and completion, report generation creates the next report version with `parent_report_id`. See `docs/architecture/report-remediation-flow.md`.

## Legal monitoring and alert boundary

Structured comparison records a reviewable legal change between same-document versions and never treats an AI/raw-PDF diff as legal truth. Confirmed change items are screened against batch product/form/HS/market/geography scope and export timing. Missing timing or ambiguous structured data requires review; retroactive effect is never inferred.

An affected batch creates a tenant-safe, deduplicated business alert for active members with `ALERT_READ`. In-app notification rows are idempotent delivery attempts. Email rows may be queued, but no external provider or fake delivery success is included. Monitoring never changes a batch status or `compliance_checks.overall_result`; formal conclusions require a separate compliance check/re-check. See `docs/architecture/legal-monitoring-flow.md`.

## Audit, RLS, and database-role boundary

Tenant queries use PostgreSQL RLS with transaction-local `app.user_id` and `app.organization_id`. Policies fail closed unless both UUIDs are valid, the row matches the selected organization, and the user has an active membership. Context must be set by a trusted backend after authentication and membership validation; database credentials are never exposed to clients.

`audit_logs`, field changes, and sensitive-access logs are append-only. Critical mutations and audit writes belong in the same database transaction. `system_job_runs` supplies idempotent, bounded-retry worker history. Passwordless logical roles separate normal application, worker, and explicit administrative access; production LOGIN roles and credentials remain deployment responsibilities.

See `docs/database/rls.md`, `docs/security/security-model.md`, and `docs/architecture/audit-flow.md`.

PDF rendering/export, frontend/dashboard, production crawling, external email/SIEM delivery, Supabase migration, and production deployment remain outside the implemented scope.
