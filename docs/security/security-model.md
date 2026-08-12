# Security Model

## Database roles

Phase 10 creates passwordless logical roles:

- `themis_app`: normal backend application access, no login, ownership, DDL, trigger control, or RLS bypass.
- `themis_worker`: explicit background-job path, no login or RLS bypass; its broad policy applies only to `system_job_runs`.
- `themis_admin`: passwordless operational role with explicit `BYPASSRLS`; it is not granted to application/worker roles.

The migration connection remains the schema owner. Production operators should create separate LOGIN roles, store credentials in a secret manager, and grant exactly one logical role as appropriate. No role password is stored in migrations or `.env.example`.

PUBLIC loses table, sequence, and function execution privileges in `public`, and PUBLIC cannot create schema objects there. Required table/function privileges are granted explicitly. New functions created by the migration owner no longer receive default PUBLIC execution.

## Defense layers

1. Authentication establishes the user outside PostgreSQL.
2. A trusted backend validates the selected active membership.
3. `SET LOCAL` provides user and organization transaction context.
4. RLS enforces tenant row visibility and write checks.
5. RBAC/domain functions enforce action permission and lifecycle rules.
6. Composite foreign keys reject cross-tenant relationships even when a proposed row itself passes RLS.
7. Immutable/append-only triggers protect historical evidence and conclusions.

RLS therefore complements rather than replaces RBAC and relational integrity.

## Existing hardening retained

- Credential, verification, reset, and session tables store hashes rather than plaintext tokens.
- IP addresses use PostgreSQL `inet`.
- Private document storage persists object keys and checksums, never signed URLs.
- Verified evidence, approved legal versions, completed checks, terminal AI runs, approved reports, alerts, and audit histories retain their existing immutability rules.
- Tenant idempotency and bounded retry counters remain enforced for extraction, AI, re-check, notifications, audit jobs, and other workers.

## Privileged execution

System and worker access is explicit. `themis_worker` may manage job rows under its dedicated policy and call the system-audit function; `themis_app` cannot call that function or claim `SYSTEM`, `WORKER`, `AI`, or `SYSTEM_ADMIN` as an audit source. Administrative RLS bypass exists only on the separate NOLOGIN `themis_admin` role.

The backend application role is not safe for direct client connections because PostgreSQL custom settings are user-settable. Client requests must reach PostgreSQL through authenticated backend code that owns transaction context selection.

## Operational remainder

Production deployment is outside Phase 10. Operators still need to create encrypted LOGIN roles, grant logical-role membership, configure connection pooling in transaction mode, rotate secrets, restrict network exposure, back up audit data, and monitor privileged-role assumption. External SIEM export is intentionally not implemented.
