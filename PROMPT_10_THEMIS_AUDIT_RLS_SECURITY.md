# PROMPT 10 — SYSTEM AUDIT + RLS + SECURITY HARDENING

Bạn là Senior PostgreSQL Security Architect + Backend Security Engineer cho dự án **Themis LexiGuard**.

## 0. Bắt buộc trước khi làm

Đọc hoàn toàn:

```text
docs/implementation-status.md
```

Sau đó inspect:

```text
db/migrations/
src/
tests/
docs/database/
docs/architecture/
README.md
.env.example
compose.yaml
```

Phase 01–09 đã hoàn thành và runtime-verified.

Hiện tại đã có:

- PostgreSQL 15 + pgvector.
- Identity / Organization / RBAC.
- Product / Market / HS.
- Export Batch + registry entity linkage.
- Immutable Document Revision + OCR/Lab/Verification foundation.
- Legal Knowledge + exact provenance.
- Deterministic Compliance Engine.
- AI/RAG + citation validation.
- Immutable Report + Remediation + Re-check.
- Legal Change Monitoring + Impact + Alerts + Notifications.
- Composite tenant-safe FKs đã được dùng ở các aggregate quan trọng.
- RLS chưa triển khai.
- System-wide audit chưa triển khai.

Không làm lại phase cũ nếu không có lỗi thật.

---

# 1. Mục tiêu Prompt 10

Chỉ triển khai:

```text
Global Audit
+
Audit Field Changes
+
Sensitive Data Access Logs
+
System Job Runs
+
PostgreSQL RLS
+
Tenant Security Context
+
Security Hardening
+
Security Tests
+
Docs
```

Không triển khai:

- Frontend
- Full REST API
- Dashboard
- Supabase migration
- crawler production
- external SIEM
- real email provider
- deployment production

Dừng sau Prompt 10.

---

# 2. Tables cần tạo

Tối thiểu:

```text
audit_logs
audit_log_changes
data_access_logs
system_job_runs
```

Không tạo `auth_audit_logs`.

Authentication events sau này dùng:

```text
audit_logs.category = AUTH
```

---

# 3. `audit_logs`

Tenant-aware global audit.

Tối thiểu:

```text
id UUID PK

organization_id UUID NULL
user_id UUID NULL

category
action

entity_type NULL
entity_id UUID NULL

result

request_id UUID NULL
trace_id TEXT NULL

ip_address INET NULL
user_agent TEXT NULL

source

metadata JSONB NULL

created_at TIMESTAMPTZ NOT NULL
```

Category:

```text
AUTH
ORGANIZATION
BATCH
DOCUMENT
LEGAL
COMPLIANCE
REPORT
REMEDIATION
MONITORING
SECURITY
SYSTEM
```

Result:

```text
SUCCESS
FAILURE
DENIED
```

Source:

```text
USER
API
WORKER
RULE_ENGINE
AI
SYSTEM
SYSTEM_ADMIN
```

Không hard-code entity type bằng FK polymorphic.

---

# 4. Audit Events tối thiểu cần support

Ví dụ:

```text
REGISTER
EMAIL_VERIFIED
LOGIN_SUCCESS
LOGIN_FAILED
PASSWORD_RESET
LOGOUT

MEMBER_INVITED
ROLE_CHANGED
MEMBER_REMOVED

BATCH_CREATED
BATCH_UPDATED

DOCUMENT_UPLOADED
DOCUMENT_REVISION_VERIFIED
OCR_VALUE_CORRECTED

COMPLIANCE_CHECK_CREATED
COMPLIANCE_CHECK_COMPLETED
RECHECK_CREATED

REPORT_GENERATED
REPORT_SUBMITTED
REPORT_APPROVED
REPORT_REJECTED

REMEDIATION_CREATED
EVIDENCE_SUBMITTED
EVIDENCE_APPROVED

LEGAL_VERSION_ADDED
LEGAL_CHANGE_DETECTED

ALERT_CREATED
ALERT_ACKNOWLEDGED
```

Không cần audit mọi SELECT bình thường.

---

# 5. `audit_log_changes`

Tạo:

```text
id UUID PK
audit_log_id UUID NOT NULL

field_name
old_value JSONB NULL
new_value JSONB NULL

created_at TIMESTAMPTZ NOT NULL
```

Mục tiêu:

```text
AUDIT EVENT
→ optional field-level changes
```

Không nhét toàn bộ before/after record vào một JSON khổng lồ nếu chỉ cần một vài field quan trọng.

---

# 6. `data_access_logs`

Dùng cho truy cập dữ liệu nhạy cảm.

Tối thiểu:

```text
id UUID PK

organization_id UUID NOT NULL
user_id UUID NOT NULL

resource_type
resource_id UUID NOT NULL

access_type

request_id UUID NULL
ip_address INET NULL

created_at TIMESTAMPTZ NOT NULL
```

Access type:

```text
VIEW
DOWNLOAD
EXPORT
PRINT
```

Chỉ log tài nguyên nhạy cảm, ví dụ:

```text
Document
Document File
Compliance Report
Legal Evidence Export
```

Không log mọi dashboard GET.

---

# 7. `system_job_runs`

Dùng cho worker/background process.

Tối thiểu:

```text
id UUID PK

job_type
job_key NULL

organization_id UUID NULL

status

idempotency_key NULL
attempt_number
max_attempts
next_retry_at NULL

started_at NULL
completed_at NULL

items_processed INTEGER NOT NULL DEFAULT 0
items_succeeded INTEGER NOT NULL DEFAULT 0
items_failed INTEGER NOT NULL DEFAULT 0

last_error_code NULL
error_message NULL
metadata JSONB NULL

created_at
updated_at
```

Status:

```text
QUEUED
RUNNING
COMPLETED
FAILED
CANCELLED
```

Dùng cho:

```text
OCR
AI
LEGAL_CHANGE_IMPACT_SCAN
NOTIFICATION_DELIVERY
EMBEDDING_GENERATION
future workers
```

Không tạo duplicate job ngoài ý muốn.

---

# 8. Append-only Audit

Bắt buộc:

```text
audit_logs
audit_log_changes
data_access_logs
```

không UPDATE/DELETE bởi application role thông thường.

Dùng PostgreSQL trigger/policy/privilege phù hợp.

Correction phải là:

```text
new audit event
```

không sửa event cũ.

---

# 9. Critical Business Transaction + Audit

Document strategy:

```text
business mutation
+
audit insert
=
same transaction
```

cho các action quan trọng như:

```text
report approval
document verification
role change
compliance check creation
remediation approval
```

Nếu hiện tại domain services chưa có centralized AuditService:
- tạo foundation tối thiểu
- không refactor toàn bộ project quá mức.

Có thể tạo:

```text
src/audit/
```

với:

```text
AuditService
DataAccessAuditService
```

Nếu hợp lý với codebase hiện tại.

---

# 10. RLS Strategy

Triển khai PostgreSQL RLS cho tenant-owned tables.

Không dùng Supabase-specific `auth.uid()` trong phase này.

Giữ PostgreSQL portable.

Dùng controlled request/transaction context, ví dụ:

```sql
SET LOCAL app.user_id = '...';
SET LOCAL app.organization_id = '...';
```

và helper functions như:

```text
current_app_user_id()
current_app_organization_id()
```

Nếu chọn cách khác, phải giải thích và test.

`SET LOCAL` phải được dùng trong transaction để tránh connection-pool context leak.

---

# 11. RLS Security Context

Tạo safe helper function(s), ví dụ:

```text
app_current_user_id()
app_current_organization_id()
```

Requirements:

- fail closed khi context thiếu
- không default sang tenant khác
- malformed UUID không làm leak data
- privileged system/admin execution phải explicit, không implicit bypass

Không để client tùy ý SET database session variables trực tiếp.

Sau này backend sẽ set context sau khi auth + membership validation.

---

# 12. Tables cần RLS

Áp dụng RLS cho tenant-owned business tables đã tồn tại.

Tối thiểu cover các nhóm:

```text
organizations
organization_members
organization_member_roles

export_batches
export_batch_items

organization_registered_entities
batch_registered_entities

documents
document_revisions
document_files
batch_documents

document_extraction_jobs
extracted_fields
lab_test_results
document_verifications
document_verification_changes

compliance_checks
compliance_check_documents
rule_executions
findings
compliance_check_events
ai_runs

compliance_reports
report_findings
report_finding_citations
report_approvals

remediation_tasks
remediation_task_assignees
remediation_evidence
remediation_reviews
remediation_task_events

batch_legal_impacts
alerts
alert_recipients
notifications

audit_logs
data_access_logs
```

Global legal/reference tables không cần tenant RLS:

```text
countries
markets
products
hs_*
legal_sources
legal_authorities
legal_documents
legal_document_versions
legal_sections
legal_requirements
regulated_substances
legal_limits
legal_citations
legal_chunks
legal_embeddings
compliance_rules
compliance_rule_versions
regulation_changes
regulation_change_items
```

Trừ khi schema thực tế có tenant column ở bảng nào đó.

---

# 13. Organization Access Policy

Một authenticated user chỉ đọc tenant data khi là active member của organization.

Conceptual:

```text
current user
→ organization_members
→ status ACTIVE
→ organization_id = current organization context
```

Không chỉ check:

```text
row.organization_id = app.organization_id
```

mà còn phải đảm bảo user thực sự có active membership.

Nếu performance cần helper/security-definer function:
- dùng `SECURITY DEFINER` cực kỳ cẩn thận
- fixed `search_path`
- least privilege
- test privilege escalation.

---

# 14. Write Policies

RLS không thay RBAC.

RLS bảo vệ:

```text
which tenant rows can be accessed
```

RBAC/domain service bảo vệ:

```text
what action user may perform
```

Không cố nhét toàn bộ permission engine vào RLS nếu làm policy phức tạp/khó maintain.

Nhưng tối thiểu:
- user không được INSERT row cho organization khác.
- user không được UPDATE row tenant khác.
- user không được DELETE row tenant khác.

`WITH CHECK` policies bắt buộc nơi applicable.

---

# 15. `organizations` RLS

Đặc biệt cẩn thận.

User chỉ thấy organization mà họ là member.

System admin có thể có bypass path riêng nếu explicit.

Không cho user A query toàn bộ `organizations`.

---

# 16. Global Legal Knowledge Read Policy

Legal/reference data là shared.

Có thể cho authenticated application role đọc global approved reference data.

Không cho tenant user update legal knowledge chỉ vì RLS không áp dụng.

Write access legal domain phải dành cho privileged backend/admin role.

Document privilege model.

---

# 17. Database Roles / Privileges

Nếu hiện tại mới có owner/superuser connection, tạo/document logical roles phù hợp, ví dụ:

```text
themis_app
themis_worker
themis_admin
```

Không nhất thiết phải hard-code password migration.

Principle:

```text
application role != database owner
```

Application role không được:
- bypass RLS
- alter schema
- disable triggers
- mutate audit history.

Worker chỉ có quyền cần thiết.

Nếu local setup chưa tách role hoàn toàn:
- implement database grants where practical
- document remaining operational setup.

---

# 18. Security Hardening

Kiểm tra và bổ sung constraint/policy cho:

- secret/token hashes, không plaintext.
- IP dùng INET.
- signed URL không lưu lâu dài.
- verified evidence immutable.
- approved report immutable.
- completed check immutable.
- terminal AI run immutable.
- legal approved version immutable.
- audit append-only.
- cross-tenant FKs.
- idempotency keys.
- retry counters.

Không duplicate trigger nếu đã tồn tại.

---

# 19. Security Tests bắt buộc

Tạo dedicated security/RLS tests.

## Tenant read isolation

1. User A đọc batch Org A được.
2. User A không đọc batch Org B.
3. User A không đọc document Org B.
4. User A không đọc finding/report/remediation Org B.
5. User A không đọc alert/notification Org B.

## Tenant write isolation

6. User A không INSERT batch cho Org B.
7. User A không attach document Org B.
8. User A không UPDATE row Org B.
9. User A không DELETE row Org B.

## Membership

10. User không phải member không đọc tenant.
11. SUSPENDED/REMOVED membership không truy cập tenant.
12. Active membership truy cập đúng tenant.
13. Chuyển organization context không bypass membership.

## Missing context

14. Không set `app.organization_id` → fail closed.
15. Không set user context → fail closed.
16. malformed context → không leak data.

## Cross-tenant integrity regression

17. Composite FKs vẫn chặn cross-tenant references.
18. RLS không che mất constraint bug.

## Global reference

19. Authenticated application role đọc allowed global reference data.
20. Application role không update legal knowledge nếu không được cấp quyền.

## Audit

21. Application user insert audit qua approved service/function được nếu strategy cho phép.
22. Application role không UPDATE audit log.
23. Application role không DELETE audit log.
24. Audit field changes append-only.
25. Data access logs append-only.

## Privilege escalation

26. Normal app role không `ALTER TABLE`.
27. Normal app role không `DISABLE TRIGGER`.
28. Normal app role không `SET row_security = off` để bypass.
29. Security-definer helpers không bị search_path hijack.

## Regression

30. Empty DB migrations PASS.
31. Migration rerun PASS.
32. Phase 01–09 tests PASS.
33. AI/domain/monitoring tests PASS.
34. New RLS/security tests PASS.

---

# 20. Performance Considerations

RLS membership checks cần indexes phù hợp.

Cân nhắc:

```text
organization_members(user_id, organization_id, status)
organization_members(organization_id, user_id, status)
```

và các tenant tables:

```text
(organization_id, id)
```

đã có/đang dùng.

Dùng `EXPLAIN` cho một vài representative queries nếu practical.

Không premature-optimize nhưng tránh policy full-table scans.

---

# 21. Supabase Compatibility

Project có thể dùng Supabase sau này.

Nhưng Prompt 10 không migrate sang Supabase.

Thiết kế RLS portable để sau này có thể map:

```text
app.user_id
→ Supabase auth.uid()
```

mà không phải rewrite domain schema.

Document:

```text
Current portable RLS strategy
Future Supabase adaptation notes
```

Không thêm Supabase SDK trong phase này.

---

# 22. Seeds

Có thể seed/reference permissions nếu cần cho:

```text
audit:read
security:audit_access
```

Nhưng không seed audit/business events.

Không seed fake sensitive access.

---

# 23. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

Tạo:

```text
docs/database/rls.md
docs/security/security-model.md
docs/architecture/audit-flow.md
```

Docs phải giải thích:

```text
tenant boundary
RLS context
membership enforcement
RLS vs RBAC
global legal reference access
database role model
audit append-only
sensitive data access logs
worker jobs
future Supabase mapping
```

---

# 24. Definition of Done

Chỉ báo DONE khi:

- audit tables hoàn thành.
- audit append-only hoạt động.
- data access logging foundation hoàn thành.
- system job runs hoàn thành.
- RLS bật trên tenant-owned tables.
- missing tenant context fail closed.
- active membership required.
- cross-tenant read/write tests PASS.
- normal app role không bypass RLS.
- global legal/reference privilege model rõ.
- application role không phải DB owner.
- security helper functions hardened.
- Phase 01–09 regression tests PASS.
- new security/RLS tests PASS.
- docs/status updated.
- không triển khai Frontend/Dashboard/Supabase migration ngoài scope.

---

# 25. Handoff bắt buộc

Khi hoàn tất, trả đúng format:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

RLS TABLES ENABLED:

SECURITY / AUDIT COMPONENTS CREATED:

TEST RESULTS:

IMPORTANT DECISIONS:

RLS CONTEXT STRATEGY:

MEMBERSHIP / TENANT STRATEGY:

DATABASE ROLE STRATEGY:

AUDIT STRATEGY:

SUPABASE COMPATIBILITY NOTES:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang Backend API / Dashboard / Frontend.
