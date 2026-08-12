# PROMPT 09 — LEGAL CHANGE MONITORING + BATCH IMPACT + ALERTS

Bạn là Senior PostgreSQL Architect + Legal Monitoring Domain Architect cho dự án **Themis LexiGuard**.

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
```

Phase 01–08 đã hoàn thành và runtime-verified.

Hiện tại đã có:

- PostgreSQL 15 + pgvector.
- Legal documents + immutable versions.
- Legal requirements/scopes/limits/citations.
- Export batches + product/form/HS/market.
- Deterministic Compliance Engine.
- AI/RAG.
- Immutable reports.
- Remediation + re-check lineage.
- Không có monitoring/alerts/notifications/dashboard.

Không làm lại phase cũ nếu không có lỗi thật.

---

# 1. Mục tiêu Prompt 09

Chỉ triển khai:

```text
Legal Version Old
→ Legal Version New
→ Regulation Change
→ Change Items
→ Scope/Impact Resolution
→ Affected Batches
→ Alerts
→ Alert Recipients
→ Notifications
→ Tests + Docs
```

Không triển khai:

- crawler production
- automatic web scraping
- Dashboard
- Frontend
- RLS hardening
- Supabase migration
- System-wide audit module
- email provider thật nếu chưa có credentials/infrastructure

Dừng sau Prompt 09.

---

# 2. Tables cần tạo

Tối thiểu:

```text
regulation_changes
regulation_change_items
batch_legal_impacts

alerts
alert_recipients
notifications
```

Có thể tạo domain services:

```text
src/monitoring/
src/alerts/
```

Không dựng full REST API.

---

# 3. `regulation_changes`

Đại diện cho một thay đổi giữa hai legal versions.

Tối thiểu:

```text
id UUID PK

legal_document_id UUID NOT NULL
from_version_id UUID NULL
to_version_id UUID NOT NULL

change_type
status

summary NULL

detected_at
confirmed_at NULL
confirmed_by NULL

created_at
updated_at
```

`change_type`:

```text
NEW
AMENDMENT
REPLACEMENT
REPEAL
EXPIRATION
```

`status`:

```text
DETECTED
ANALYZING
CONFIRMED
IGNORED
```

Yêu cầu:

- `from_version_id` và `to_version_id` phải thuộc cùng `legal_document_id`.
- `from_version_id != to_version_id`.
- `to_version_id` là version mới hơn theo lineage/version policy.
- Không cho cross-document comparison.

Nếu `change_type = NEW`, `from_version_id` được phép NULL.

---

# 4. `regulation_change_items`

Một regulation change có nhiều item.

Tối thiểu:

```text
id UUID PK
regulation_change_id UUID NOT NULL

change_category

old_requirement_id UUID NULL
new_requirement_id UUID NULL

old_legal_limit_id UUID NULL
new_legal_limit_id UUID NULL

severity
change_summary

requires_reassessment BOOLEAN NOT NULL DEFAULT FALSE

created_at
```

`change_category` tối thiểu:

```text
REQUIREMENT_ADDED
REQUIREMENT_REMOVED
REQUIREMENT_MODIFIED
LIMIT_INCREASED
LIMIT_DECREASED
SCOPE_CHANGED
EFFECTIVE_DATE_CHANGED
OTHER
```

Severity:

```text
INFO
LOW
MEDIUM
HIGH
CRITICAL
```

Không bắt buộc mọi item phải có limit.

Enforce shape hợp lý:

- requirement change phải có old/new requirement phù hợp.
- limit change phải có old/new limit phù hợp.
- không cho tất cả reference đều NULL nếu category cần provenance.

Không copy legal truth vào free-text nếu đã có relational references.

---

# 5. Change Detection Strategy

Không triển khai crawler.

Phase này chỉ xử lý khi:

```text
new legal_document_version đã tồn tại trong DB
```

Tạo service/function kiểu:

```text
LegalChangeService.compareVersions(fromVersionId, toVersionId)
```

MVP comparison dựa trên structured legal data:

```text
legal_requirements
requirement_scopes
legal_limits
effective dates
```

Không diff raw PDF bằng AI rồi coi đó là legal truth.

Cho phép:
- deterministic diff
- manual confirmation

Nếu diff không chắc chắn:

```text
status = ANALYZING
```

hoặc item cần review.

Không tự động CONFIRMED khi mapping không rõ.

---

# 6. `batch_legal_impacts`

Tenant-owned.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL

batch_id UUID NOT NULL
change_item_id UUID NOT NULL

impact_status
impact_reason NULL

previous_check_id UUID NULL

recommended_action NULL

assessed_at
created_at
updated_at
```

Impact status:

```text
POTENTIALLY_AFFECTED
AFFECTED
NOT_AFFECTED
REVIEW_REQUIRED
```

Recommended action:

```text
NONE
REVIEW_DOCUMENTS
NEW_LAB_TEST
RECHECK
MANUAL_REVIEW
```

Composite tenant-safe FK tới:

```text
export_batches
compliance_checks
```

Nếu `previous_check_id` có giá trị:
- phải cùng organization
- cùng batch.

Unique hợp lý:

```text
UNIQUE(organization_id, batch_id, change_item_id)
```

---

# 7. Impact Resolution Strategy

Phải reuse scope semantics Phase 05/06:

```text
within one scope row:
populated fields = AND

NULL = wildcard

multiple scope rows = OR
```

Impact resolution có thể dùng:

```text
product
product_form
hs_code
market
origin
destination
planned/actual export date
```

Không được đánh dấu batch là `NON_COMPLIANT` chỉ vì luật đổi.

Monitoring chỉ được tạo:

```text
AFFECTED
POTENTIALLY_AFFECTED
REVIEW_REQUIRED
```

Formal compliance result chỉ đến từ:

```text
new Compliance Check / Re-check
```

---

# 8. Effective Date Policy

Impact assessment phải xem:

```text
new legal requirement/limit effective_from
```

và batch timing.

MVP policy phải document rõ:

- batch planned export date trong/after effective period → có thể affected.
- batch đã hoàn tất trước effective date → thường không affected bởi rule mới, trừ khi requirement có retroactive semantics được explicitly modeled.
- nếu export date thiếu/không chắc → REVIEW_REQUIRED.

Không tự suy diễn retroactive law.

---

# 9. `alerts`

Tenant-owned.

Tạo:

```text
id UUID PK
organization_id UUID NOT NULL

batch_id UUID NULL

regulation_change_id UUID NULL
change_item_id UUID NULL
impact_id UUID NULL

alert_type
severity

title
message

status

created_at
acknowledged_at NULL
resolved_at NULL
```

Alert type:

```text
LEGAL_CHANGE
BATCH_AT_RISK
DOCUMENT_EXPIRING
COMPLIANCE_FAILURE
REMEDIATION_DUE
SYSTEM
```

Prompt 09 tập trung chủ yếu:

```text
LEGAL_CHANGE
BATCH_AT_RISK
```

Status:

```text
OPEN
ACKNOWLEDGED
RESOLVED
DISMISSED
```

Alert phải tenant-safe.

---

# 10. Khi nào tạo Alert?

Nếu legal change confirmed nhưng:

```text
không có batch affected
```

thì:

```text
regulation_changes + change_items vẫn lưu
alerts không bắt buộc tạo
```

Đây là behavior bắt buộc.

Không spam user bằng alert rủi ro nếu không có batch liên quan.

Có thể vẫn lưu một informational legal-update record qua regulation change itself.

---

# 11. Alert Deduplication

Không tạo cùng một alert lặp lại mỗi lần worker chạy.

Dùng idempotency/unique strategy phù hợp, ví dụ dựa trên:

```text
organization_id
impact_id
alert_type
```

hoặc canonical dedup key.

Document quyết định.

---

# 12. `alert_recipients`

Tạo:

```text
organization_id UUID NOT NULL
alert_id UUID NOT NULL
user_id UUID NOT NULL

is_read BOOLEAN NOT NULL DEFAULT FALSE
read_at NULL
acknowledged_at NULL

created_at
```

PK/unique:

```text
(organization_id, alert_id, user_id)
```

Recipient phải thuộc organization.

MVP recipient policy:

- OWNER
- MANAGER
- COMPLIANCE

hoặc permission-based equivalent nếu RBAC đã hỗ trợ.

Ưu tiên permission resolution hơn hard-code role trong nhiều nơi.

---

# 13. `notifications`

Notification khác Alert.

```text
Alert = persistent business event
Notification = delivery attempt
```

Tạo:

```text
id UUID PK
organization_id UUID NOT NULL

user_id UUID NOT NULL
alert_id UUID NULL

channel

title
message

status

idempotency_key NULL
attempt_number
max_attempts
next_retry_at NULL

sent_at NULL
delivered_at NULL
read_at NULL

last_error_code NULL
failure_reason NULL

created_at
updated_at
```

Channel:

```text
IN_APP
EMAIL
```

Status:

```text
PENDING
SENT
DELIVERED
FAILED
READ
CANCELLED
```

Prompt này không cần email provider thật.

IN_APP phải hoạt động ở DB/domain level.

---

# 14. Notification idempotency/retry

Enforce:

```text
attempt_number >= 1
max_attempts >= 1
attempt_number <= max_attempts
```

Idempotency unique tenant-safe nếu key có giá trị.

Không tạo duplicate delivery khi worker retry.

Terminal notification history không nên bị rewrite tùy ý.

---

# 15. Domain Services

Nếu phù hợp với codebase hiện tại, tạo tối thiểu:

```text
LegalChangeService
BatchImpactService
AlertService
NotificationService
```

Responsibilities:

```text
LegalChangeService
→ compare structured legal versions

BatchImpactService
→ resolve affected batches

AlertService
→ create deduplicated tenant alerts + recipients

NotificationService
→ create delivery records
```

Không tích hợp external email provider thật nếu chưa có infrastructure.

---

# 16. Không dùng AI để tự kết luận impact

AI có thể được dùng tương lai để hỗ trợ interpretation, nhưng Prompt 09:

```text
impact resolution = deterministic structured data first
```

Không gọi Gemini để quyết định:

```text
batch is NON_COMPLIANT
```

hoặc để invent legal change.

---

# 17. Tests bắt buộc

## Regulation change

1. Valid same-document version comparison tạo được.
2. Cross-document version comparison bị chặn.
3. `NEW` cho phép from_version NULL.
4. from == to bị chặn.
5. Change item giữ valid requirement/limit provenance.
6. Invalid change-item shape bị chặn.

## Impact

7. Batch matching product/form/market scope → affected.
8. Batch ngoài scope → not affected.
9. Specific/wildcard semantics reuse đúng.
10. Planned export trước effective date → not affected theo MVP policy.
11. Missing/ambiguous date → review required.
12. Cross-tenant previous_check linkage bị chặn.
13. Duplicate batch/change impact bị chặn.

## Monitoring safety

14. Legal change không trực tiếp sửa `compliance_checks.overall_result`.
15. Affected batch không tự động trở thành NON_COMPLIANT.
16. Formal status vẫn cần new compliance check.

## Alerts

17. Affected impact tạo alert.
18. No affected batch → không bắt buộc tạo risk alert.
19. Duplicate alert worker run không tạo duplicate.
20. Cross-tenant alert linkage bị chặn.

## Recipients

21. Recipient thuộc organization được attach.
22. User ngoài organization bị chặn theo chosen strategy.
23. Duplicate recipient bị chặn.

## Notifications

24. In-app notification tạo được.
25. Duplicate idempotency key bị chặn.
26. Retry counter invalid bị chặn.
27. Notification giữ alert/user/organization consistency.
28. No email credential vẫn không làm DB/domain tests fail.

## Regression

29. Empty DB migrations PASS.
30. Migration rerun PASS.
31. Phase 01–08 database tests PASS.
32. Existing AI/domain tests PASS.
33. New monitoring domain tests PASS.

---

# 18. Seeds

Không seed:

- legal changes production
- impacted batches
- alerts
- notifications

Có thể seed permission mới nếu cần:

```text
legal_change:read
alert:read
alert:acknowledge
```

và map idempotently vào system roles phù hợp.

Không seed fake legal facts.

---

# 19. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

Nếu tạo domain services:

```text
docs/architecture/legal-monitoring-flow.md
```

Docs phải giải thích:

```text
legal version change
vs
change item
vs
batch impact
vs
alert
vs
notification

effective-date impact policy
scope resolution
why legal change != non-compliance
alert deduplication
recipient policy
notification retry/idempotency
```

---

# 20. Definition of Done

Chỉ báo DONE khi:

- `regulation_changes` hoàn thành.
- `regulation_change_items` hoàn thành.
- Structured version comparison foundation hoạt động.
- Batch impact resolution hoạt động.
- Legal change không trực tiếp sửa compliance result.
- Alerts tenant-safe + deduplicated.
- Recipients tenant-safe.
- Notifications có retry/idempotency foundation.
- No-affected-batch flow không tạo fake risk alert.
- Phase 01–08 regression tests PASS.
- Phase 09 tests PASS.
- Docs/ERD/status updated.
- Không triển khai Dashboard/Frontend/RLS/crawler ngoài scope.
- Không seed fake production legal/monitoring data.

---

# 21. Handoff bắt buộc

Khi hoàn tất, trả đúng format:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

DOMAIN COMPONENTS CREATED:

TEST RESULTS:

IMPORTANT DECISIONS:

LEGAL CHANGE DETECTION STRATEGY:

BATCH IMPACT STRATEGY:

ALERT DEDUPLICATION STRATEGY:

NOTIFICATION STRATEGY:

SAFETY STRATEGY:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang Dashboard / Frontend / RLS.
