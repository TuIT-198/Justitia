# Portable PostgreSQL RLS

Phase 10 enables row-level security on every implemented tenant-owned aggregate and on tenant-derived citation/audit children. The design is ordinary PostgreSQL 15 and does not depend on Supabase functions.

## Transaction context

After authenticating a request and validating membership, the backend opens a transaction and sets both values locally:

```sql
BEGIN;
SET LOCAL app.user_id = 'authenticated-user-uuid';
SET LOCAL app.organization_id = 'selected-organization-uuid';
-- business statements and audit insert
COMMIT;
```

`SET LOCAL` is mandatory: transaction end clears the values before a pooled connection is reused. Backend database credentials must never be exposed to browsers or other untrusted clients. Custom PostgreSQL settings are not an authentication mechanism by themselves; the trusted backend binds authenticated identity to the transaction.

`app_current_user_id()` and `app_current_organization_id()` return NULL for missing, empty, or malformed values. `app_tenant_access_allowed(organization_id)` also requires:

- the row organization equals the selected organization context;
- the current user context is a valid UUID;
- an `ACTIVE` membership exists for that exact user and organization.

Any failed condition returns false. Switching only the organization context cannot bypass membership.

## Policy coverage

RLS is enabled for:

- organizations, members, and member roles;
- export batches/items and tenant registry links;
- documents, revisions, files, batch attachments, OCR/lab/verification records;
- checks, evidence/legal snapshots, executions, findings/citations, events, and AI runs;
- reports, report snapshots/approvals, remediation records, evidence/reviews/events;
- batch impacts, alerts, recipients, and notifications;
- tenant audit logs, audit field changes, sensitive-access logs, and job visibility.

Tables with `organization_id` use a common `USING` and `WITH CHECK` policy. `organizations` applies the check to `id`. `finding_citations` and `audit_log_changes` resolve the protected tenant through their parent. System job rows use tenant visibility for the application role and a separate explicit worker policy.

RLS limits which tenant rows are accessible. It does not replace RBAC or domain-state validation. An active member may still lack permission to approve a report, manage membership, or acknowledge an alert; those decisions remain in permission-aware domain functions/services.

## Hardened helpers

Membership and parent-resolution helpers are `SECURITY DEFINER` only to avoid recursive RLS on `organization_members`. Each helper:

- uses `SET search_path = pg_catalog, public`;
- references protected tables with explicit `public.` qualification;
- is owned by the migration/schema owner, not `themis_app`;
- has PUBLIC execution revoked;
- returns only a boolean or parsed context UUID.

Application users cannot create objects in `public`, own tenant tables, disable triggers, alter schema, or bypass RLS. Setting `row_security=off` as `themis_app` causes protected queries to fail instead of exposing rows.

## Global reference data

`themis_app` has SELECT-only access to shared geography, product/HS, document-type, measurement, legal, rule, and regulation-change reference tables. It has no INSERT/UPDATE/DELETE grant on legal knowledge. Legal administration uses the explicit administrative path; tenant membership alone never grants legal-write authority.

## Future Supabase mapping

The domain schema and policies are independent of Supabase. A future migration can replace `app_current_user_id()` internally with a trusted `auth.uid()` mapping while retaining `app_current_organization_id()` and the active-membership predicate. Until that dedicated migration exists, do not mix Supabase session assumptions into these policies.
