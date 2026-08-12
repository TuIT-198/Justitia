# Legal Monitoring Flow

Phase 09 adds deterministic monitoring after a new legal document version already exists in PostgreSQL. It does not crawl sources, interpret raw PDFs with AI, or produce a compliance conclusion.

```text
old legal version + new legal version
  -> structured requirement/scope/limit comparison
  -> regulation change in ANALYZING
  -> manual confirmation
  -> tenant batch impact assessment
  -> deduplicated alert and permission-based recipients
  -> idempotent in-app/email delivery record
  -> separately requested compliance re-check, when appropriate
```

## Domain boundaries

- A `regulation_changes` row identifies the exact same-document version pair. A `NEW` change has no old version. Direct version lineage is required for amendments.
- A `regulation_change_items` row identifies one structured requirement, scope, effective-date, or normalized-limit change. Relational references retain legal provenance; summary text is explanatory only.
- A `batch_legal_impacts` row is a tenant-owned screening result for one batch/change item. It is not a compliance finding.
- An `alerts` row is the persistent tenant business event. Re-running a worker does not create the same batch-risk event again.
- A `notifications` row is a delivery attempt for an alert recipient. It is not the alert itself.

## Change detection and confirmation

`compare_legal_versions` compares structured fingerprints made from requirements, their scope rows, and legal limits. Added and removed fingerprints become reviewable change items. The result starts as `ANALYZING`; uncertain mappings are never auto-confirmed. A reviewer confirms only a reviewed (`APPROVED`, `ACTIVE`, or `UPCOMING`) target legal version.

Raw PDF diffing, AI-generated legal changes, and production crawling are outside this phase. No production legal or monitoring records are seeded.

## Scope and effective-date policy

Impact assessment reuses the established semantics:

- populated fields within one scope row are `AND`;
- `NULL` is a wildcard for that dimension;
- multiple scope rows are `OR`.

Matching may use product, form, HS code, origin, destination, market, and batch timing. Actual export date takes precedence over planned export date. A batch before the new effective date is `NOT_AFFECTED`. Missing legal or export timing is `REVIEW_REQUIRED`. No retroactive effect is inferred. Missing HS data that could match an explicit HS scope is also review-required rather than guessed.

## Compliance safety

Monitoring writes only `batch_legal_impacts`, alerts, recipients, and delivery history. It never updates `compliance_checks.overall_result` or a batch lifecycle status. `AFFECTED` means the batch should be reviewed under the legal change; it does not mean `NON_COMPLIANT`. A formal outcome still requires a new compliance check or re-check with newly selected evidence and legal snapshots.

## Alerts and recipients

Risk alerts are created only for `AFFECTED`, `POTENTIALLY_AFFECTED`, or `REVIEW_REQUIRED` impacts belonging to a confirmed change. A confirmed change with no such batch impact creates no risk alert. A partial unique index on `(organization_id, impact_id, alert_type)` prevents duplicate batch-risk events while allowing future non-impact alerts.

Recipient selection resolves the `ALERT_READ` permission for active organization members. The permission seed grants it to OWNER, MANAGER, and COMPLIANCE. Composite foreign keys and validation prevent cross-tenant alert, recipient, previous-check, and notification links.

## Notification idempotency and retry

`create_in_app_notifications_for_alert` creates one pending delivery per recipient using a canonical tenant-scoped idempotency key. Retry counters must satisfy `1 <= attempt_number <= max_attempts`. Lifecycle transitions are explicit; recipient/content identity is immutable and terminal history cannot be rewritten or deleted.

`EMAIL` delivery records can be queued without credentials, but this phase includes no provider or success simulation. An external worker may be added only when real infrastructure exists.
