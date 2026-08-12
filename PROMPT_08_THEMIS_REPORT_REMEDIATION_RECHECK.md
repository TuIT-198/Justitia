# PROMPT 08 — REPORT + REMEDIATION + RE-CHECK

Bạn là Senior PostgreSQL Architect + Backend Domain Architect cho dự án **Themis LexiGuard**.

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
docs/ai/
README.md
```

Phase 01–07 đã hoàn thành và runtime-verified.

Hiện tại đã có:

- PostgreSQL 15 + pgvector 0.8.1.
- Migrations 001–017.
- Identity / Organization / RBAC.
- Product / Market / HS.
- Export Batch + Registry.
- Immutable Document Revision + private file metadata.
- Extraction / Lab / Human Verification.
- Measurement normalization.
- Legal Knowledge + exact provenance/citations.
- Deterministic Compliance Engine.
- Immutable compliance evidence/legal snapshots.
- Rule executions + findings + citations.
- AI/RAG + Gemini provider abstraction.
- AI findings chỉ VALIDATED khi citation hợp lệ trong legal snapshot.
- Completed checks không thể bị rewrite.

Không làm lại phase cũ nếu không có lỗi thực sự.

---

# 1. Mục tiêu Prompt 08

Chỉ triển khai:

```text
Completed Compliance Check
→ Compliance Report
→ Finding Snapshot
→ Citation Snapshot
→ Submission / Approval
→ Immutable Approved Report
→ Remediation Task
→ Assignee
→ Verified Evidence
→ Review
→ Re-check
→ New Check + New Report lineage
```

Không triển khai:

- Legal Change Monitoring
- Alerts / Notifications
- Dashboard
- Frontend
- RLS hardening
- Supabase migration
- PDF renderer/export
- crawler

Dừng sau Prompt 08.

---

# 2. Tables cần tạo

Tối thiểu:

```text
compliance_reports
report_findings
report_finding_citations
report_approvals

remediation_tasks
remediation_task_assignees
remediation_evidence
remediation_reviews
remediation_task_events
```

Có thể thêm domain JS modules/services tối thiểu nếu cần để test transaction/workflow.

Không dựng full REST API trong phase này.

---

# 3. `compliance_reports`

Tenant-owned.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL

check_id UUID NOT NULL
batch_id UUID NOT NULL
parent_report_id UUID NULL

version_number INTEGER NOT NULL
report_code TEXT NOT NULL

status
overall_result

title
executive_summary NULL

submission_round INTEGER NOT NULL DEFAULT 0

generated_by
generated_at

submitted_at NULL
approved_at NULL
approved_by UUID NULL

created_at
updated_at
```

Status:

```text
DRAFT
PENDING_APPROVAL
APPROVED
REJECTED
```

`overall_result` phải snapshot từ completed check:

```text
COMPLIANT
ACTION_REQUIRED
NON_COMPLIANT
MANUAL_REVIEW_REQUIRED
```

Không cho report tự đặt result khác check.

Yêu cầu:

```sql
UNIQUE (organization_id, id)
UNIQUE (organization_id, check_id)
UNIQUE (organization_id, batch_id, version_number)
```

Composite tenant-safe FK tới:

```text
compliance_checks
export_batches
```

Một check có:

```text
0..1 report
```

Check chưa completed hoặc failed có thể chưa có report.

---

# 4. Report lineage

Re-check tạo:

```text
Check #2.parent_check_id = Check #1

Report v2.parent_report_id = Report v1
```

`parent_report_id` phải:

- cùng organization
- cùng batch
- version trước đó hợp lệ

Không sửa Report v1 để biến nó thành v2.

Không dùng `SUPERSEDED` để mutate approved history.

Latest report được xác định bằng version/order query.

---

# 5. `report_findings`

Report phải snapshot finding content.

Tạo:

```text
id UUID PK
organization_id UUID NOT NULL

report_id UUID NOT NULL
finding_id UUID NOT NULL

display_order INTEGER NOT NULL

source_type_snapshot
finding_type_snapshot
title_snapshot
description_snapshot
severity_snapshot
validation_status_snapshot

actual_value_snapshot NULL
expected_value_snapshot NULL
unit_snapshot NULL
remediation_snapshot NULL

created_at
```

Mục tiêu:

```text
Approved report
không phụ thuộc vào finding row hiện tại để render lại.
```

Finding FK vẫn giữ provenance, nhưng UI/report dùng snapshot fields.

Không snapshot PASS rule executions thành report findings.

---

# 6. `report_finding_citations`

Đây là bắt buộc.

Tạo:

```text
id UUID PK
organization_id UUID NOT NULL

report_finding_id UUID NOT NULL
source_citation_id UUID NOT NULL

is_primary BOOLEAN NOT NULL DEFAULT FALSE

citation_code_snapshot
display_label_snapshot
quote_excerpt_snapshot NULL
canonical_reference_snapshot NULL

legal_document_id
legal_document_version_id
legal_section_id
legal_requirement_id NULL

legal_version_content_hash_snapshot NULL
source_file_checksum_snapshot NULL

created_at
```

Mục tiêu:

```text
Report v1 APPROVED
→ citation hiển thị chính xác như lúc report được tạo/duyệt
→ legal metadata sau này không làm report lịch sử thay đổi
```

Phải validate snapshot provenance:

```text
citation
→ section
→ legal version
→ document
→ source
```

và legal version phải thuộc snapshot của check tạo report.

Không chấp nhận free-text citation không có source citation row.

---

# 7. Report generation rules

Chỉ generate report từ:

```text
compliance_checks.status = COMPLETED
```

và có `overall_result`.

Khi generate:

1. Tạo report DRAFT.
2. Copy overall result.
3. Snapshot findings.
4. Snapshot citations của từng finding.
5. Giữ exact provenance.
6. Audit phase sau sẽ bổ sung global audit; hiện có thể dùng domain history/table hiện có nếu phù hợp, nhưng không tạo System Audit module mới.

Nếu finding `VALIDATED` mà citation invariant bị lỗi:
- report generation phải fail
- không tạo report thiếu legal basis.

Ưu tiên transaction atomic:

```text
report
+ report_findings
+ report_finding_citations
```

---

# 8. Approval workflow

MVP:

```text
ONE_APPROVER
```

Authorized role/permission policy:

```text
MANAGER hoặc OWNER
```

Nếu schema RBAC đã có permission phù hợp, reuse permission.

Nếu chưa có permission cụ thể:
- seed một permission reference hợp lý, ví dụ `report:approve`
- map vào OWNER/MANAGER bằng idempotent seed migration
- không hard-code role check khắp domain code.

Flow:

```text
DRAFT
→ PENDING_APPROVAL
→ APPROVED
```

hoặc:

```text
PENDING_APPROVAL
→ REJECTED
→ DRAFT
→ PENDING_APPROVAL
```

Mỗi lần submit mới:

```text
submission_round += 1
```

---

# 9. `report_approvals`

Tạo:

```text
id UUID PK
organization_id UUID NOT NULL

report_id UUID NOT NULL
submission_round INTEGER NOT NULL

reviewer_id UUID NOT NULL

decision
comment NULL

created_at
```

Decision:

```text
APPROVED
REJECTED
```

Constraint:

```text
UNIQUE (
  organization_id,
  report_id,
  submission_round,
  reviewer_id
)
```

Một reviewer không tạo hai quyết định mâu thuẫn trong cùng round.

Approval row là history, không overwrite.

Final report state phải phù hợp decision hiện tại.

---

# 10. Approved Report Immutability

Khi report:

```text
APPROVED
```

không cho UPDATE/DELETE:

```text
compliance_reports
report_findings
report_finding_citations
report_approvals
```

trừ append-only semantics hợp lệ nếu thực sự cần.

Tốt nhất:
- approved report snapshot hoàn toàn khóa
- correction/reassessment = re-check + report mới.

Test DB trigger/policy bắt buộc.

---

# 11. `remediation_tasks`

Tenant-owned.

Tạo:

```text
id UUID PK
organization_id UUID NOT NULL

batch_id UUID NOT NULL
report_id UUID NOT NULL
finding_id UUID NOT NULL

title
description NULL

priority
status

due_date NULL

created_by UUID NOT NULL

created_at
updated_at
completed_at NULL
```

Priority:

```text
LOW
MEDIUM
HIGH
CRITICAL
```

Status:

```text
OPEN
IN_PROGRESS
EVIDENCE_SUBMITTED
UNDER_REVIEW
APPROVED
REJECTED
CANCELLED
```

MVP task bắt buộc gắn:

```text
report + finding
```

Finding phải thuộc check/report lineage tương ứng.

Không cho Org A task tham chiếu Report/Finding Org B.

---

# 12. `remediation_task_assignees`

Một task có thể nhiều assignee.

Tạo:

```text
organization_id
task_id
user_id

assigned_by
assigned_at
```

PK/unique:

```text
(organization_id, task_id, user_id)
```

Assignee phải là active member của organization tại thời điểm assign theo service/domain policy.

Enforce relational tenant consistency nơi practical.

---

# 13. `remediation_evidence`

Evidence phải dùng document model có sẵn.

Tạo:

```text
id UUID PK
organization_id UUID NOT NULL

task_id UUID NOT NULL

document_id UUID NOT NULL
document_revision_id UUID NOT NULL
verification_id UUID NOT NULL

submitted_by UUID NOT NULL
description NULL

status

submitted_at
created_at
```

Status:

```text
SUBMITTED
ACCEPTED
REJECTED
```

Bắt buộc:

```text
document_revision = VERIFIED
verification = VERIFIED
```

và:

```text
document
revision
verification
task
```

đều cùng organization.

Evidence submission phải reference **exact verified revision**, không chỉ document identity.

Không overwrite evidence cũ khi có evidence mới.

---

# 14. `remediation_reviews`

Tạo:

```text
id UUID PK
organization_id UUID NOT NULL

task_id UUID NOT NULL
reviewer_id UUID NOT NULL

decision
comment NULL

reviewed_at
created_at
```

Decision:

```text
APPROVED
REJECTED
CHANGES_REQUESTED
```

Reviewer phải có permission phù hợp theo RBAC policy.

Review history append-only.

Task chỉ được `APPROVED` khi required remediation evidence đã được verified và accepted theo chosen workflow.

---

# 15. `remediation_task_events`

Append-only timeline:

```text
id UUID PK
organization_id UUID NOT NULL

task_id UUID NOT NULL

event_type
from_status NULL
to_status NULL

actor_user_id UUID NULL
metadata JSONB NULL

created_at
```

Examples:

```text
TASK_CREATED
ASSIGNEE_ADDED
TASK_STARTED
EVIDENCE_SUBMITTED
EVIDENCE_REJECTED
EVIDENCE_ACCEPTED
REVIEW_APPROVED
REVIEW_REJECTED
TASK_APPROVED
RECHECK_CREATED
```

Không UPDATE/DELETE event history.

---

# 16. Re-check policy

Re-check không phải UPDATE check cũ.

Flow:

```text
Report v1
→ remediation tasks
→ verified evidence
→ remediation approved
→ create Compliance Check #2
```

Check #2:

```text
parent_check_id = Check #1
same organization
same batch
new check_number
new idempotency key if applicable
```

Sau đó phase compliance processing sẽ snapshot:

```text
new verified evidence revisions
+
applicable legal versions
```

Không copy mù toàn bộ old snapshots nếu evidence/law đã thay đổi.

Phase này có thể tạo domain service/helper để tạo re-check shell transactionally.

Không tự động chạy deterministic/AI engine nếu chưa có orchestration layer.

---

# 17. Re-check gate

MVP policy:

Re-check được phép khi:

```text
source report exists
AND source check is COMPLETED
AND report belongs to same batch
AND required remediation tasks are not unresolved
AND evidence required by tasks is VERIFIED/ACCEPTED
```

Nếu report không có remediation task:
- re-check có thể được cho phép bởi authorized user nếu business flow cần, nhưng document rõ.

Không tự đoán evidence nào dùng trong check mới; snapshot selection sẽ do compliance orchestration/API phase quyết định.

---

# 18. Report v2

Không tạo Report v2 ngay khi tạo re-check shell.

Flow đúng:

```text
Re-check #2 created
→ processing
→ completed
→ generate Report v2
```

Khi generate:

```text
parent_report_id = Report v1
version_number = previous + 1
```

Report v1 giữ nguyên byte-for-byte về logical snapshot.

---

# 19. Tenant-safe constraints

Các bảng mới tenant-owned đều có:

```text
organization_id
```

Dùng composite FK cho:

```text
report → check
report → batch
report → parent report

report finding → report
report finding → finding

task → batch/report/finding

evidence → task/document/revision/verification

review → task
events → task
```

Không cho cross-tenant association.

RLS vẫn deferred.

---

# 20. Tests bắt buộc

## Report

1. Completed check tạo report được.
2. Non-completed check không tạo report.
3. Report overall result phải khớp check.
4. Một check không có hai report.
5. Report version unique trong organization/batch.
6. Parent report phải cùng org/batch.

## Finding snapshot

7. Report finding snapshot giữ content độc lập.
8. Finding không thuộc check report bị chặn.
9. Validated finding citation snapshot được tạo đầy đủ.

## Citation snapshot

10. Citation ngoài check legal snapshot bị chặn.
11. Citation/version/section provenance mismatch bị chặn.
12. Report generation fail nếu validated finding thiếu citation.
13. Source citation thay đổi không làm approved report snapshot thay đổi.

## Approval

14. DRAFT → PENDING_APPROVAL.
15. Submission round tăng đúng.
16. Duplicate reviewer decision trong same round bị chặn.
17. APPROVED report khóa mutation.
18. REJECTED report có thể quay lại DRAFT/resubmit theo policy.

## Remediation

19. Task phải cùng tenant/report/finding.
20. Cross-tenant task reference bị chặn.
21. Multiple assignees supported.
22. Duplicate assignee bị chặn.
23. Evidence phải là exact verified revision.
24. Unverified revision không được submit làm accepted remediation evidence.
25. Cross-tenant evidence linkage bị chặn.
26. Reviews append-only.
27. Task events append-only.

## Re-check

28. Re-check tạo row mới, không sửa old check.
29. parent_check phải cùng tenant/batch.
30. Unresolved remediation chặn re-check theo policy.
31. Approved remediation cho phép tạo re-check.
32. Old check/report remain unchanged.
33. Completed re-check có thể generate report version tiếp theo với parent report đúng.

## Regression

34. Empty DB migrations PASS.
35. Migration rerun PASS.
36. Phase 01–07 tests PASS.
37. Nếu thêm JS domain modules: Node tests PASS.

---

# 21. Domain services nếu cần

Nếu để test transaction/workflow rõ hơn, có thể tạo tối thiểu:

```text
src/reports/
src/remediation/
```

Ví dụ:

```text
ReportService
RemediationService
RecheckService
```

Nhưng:

- không dựng full Express API
- không tạo fake endpoints
- không thay đổi AI architecture hiện tại
- giữ dependency footprint nhỏ.

---

# 22. Seeds

Không seed:

- reports
- findings
- remediation tasks
- fake compliance results
- legal values

Có thể bổ sung idempotent RBAC permissions cần thiết:

```text
report:read
report:submit
report:approve
remediation:create
remediation:review
compliance:recheck
```

nếu permission catalog hiện tại cần.

Không phá system-defined role strategy.

---

# 23. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

Nếu có domain modules:

```text
docs/architecture/report-remediation-flow.md
```

Docs phải giải thích:

```text
check → report 0..1
report version lineage
finding snapshot
citation snapshot
submission round
approved immutability
remediation evidence exact revision
re-check lineage
why old history never changes
```

---

# 24. Definition of Done

Chỉ báo DONE khi:

- report tables hoàn thành.
- Finding + citation snapshot hoàn thành.
- Report generation từ completed check được test.
- Approval rounds hoạt động.
- Approved report immutable.
- Remediation tasks/assignees/evidence/reviews/events hoạt động.
- Evidence bắt buộc exact verified revision.
- Re-check tạo independent check mới.
- Old check/report không bị sửa.
- Report v2 lineage hoạt động sau completed re-check.
- Tenant-safe composite FKs hoạt động.
- Phase 01–07 regression tests PASS.
- Phase 08 tests PASS.
- Docs/ERD/status updated.
- Không triển khai monitoring/dashboard/frontend ngoài scope.
- Không seed fake production data.

---

# 25. Handoff bắt buộc

Khi hoàn tất, trả đúng format:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

DOMAIN COMPONENTS CREATED:

TEST RESULTS:

IMPORTANT DECISIONS:

REPORT SNAPSHOT STRATEGY:

APPROVAL STRATEGY:

REMEDIATION EVIDENCE STRATEGY:

RE-CHECK STRATEGY:

IMMUTABILITY STRATEGY:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang Legal Monitoring / Alerts.
