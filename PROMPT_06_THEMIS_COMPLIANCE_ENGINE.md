# PROMPT 06 — DETERMINISTIC COMPLIANCE ENGINE + IMMUTABLE CHECK SNAPSHOT

Bạn là Senior PostgreSQL Database Architect + Compliance Domain Architect cho dự án **Themis LexiGuard**.

## 0. Bắt buộc trước khi làm

Đọc hoàn toàn:

```text
docs/implementation-status.md
```

Sau đó inspect:

```text
db/migrations/
docs/database/
tests/database/
README.md
```

Phase 01–05 đã hoàn thành và runtime-verified.

Hiện tại đã có:

- PostgreSQL 15 baseline.
- Identity / Organization / RBAC.
- Country / Market / Product / HS.
- Export Batch + registry entity linkage.
- Document identity + immutable revision + private file metadata.
- Extraction / lab result / human verification / measurement units.
- Legal Knowledge:
  - official source
  - authority
  - legal document/version/file
  - Article/Clause/Point hierarchy
  - requirement/scope/parameter
  - regulated substances
  - legal limits
  - citations
  - market entity approval provenance
- Verified document evidence và approved legal knowledge đã có immutability protection.
- Chưa có Compliance Engine, AI, RAG, Report, Remediation, Monitoring.

Không sửa lại phase cũ nếu không phát hiện lỗi thật.

---

# 1. Mục tiêu Prompt 06

Chỉ triển khai deterministic compliance foundation:

```text
Compliance Rule
→ Rule Version
→ Compliance Check
→ Immutable Document Snapshot
→ Immutable Legal-Version Snapshot
→ Rule Executions
→ Deterministic Findings
→ Legal Citations
→ Overall Result
→ Check Events
→ Tests + Docs
```

Không triển khai:

- Gemini / AI runs
- RAG chunks/embeddings
- Reports
- Remediation
- Legal change monitoring
- Alerts
- Dashboard
- RLS
- Backend/API

Dừng sau Prompt 06.

---

# 2. Tables cần tạo

Tối thiểu:

```text
compliance_rules
compliance_rule_versions

compliance_checks
compliance_check_documents
compliance_check_legal_versions

rule_executions

findings
finding_citations

compliance_check_events
```

---

# 3. `compliance_rules`

Tạo rule identity ổn định:

```text
id UUID PK
rule_code
legal_requirement_id UUID NOT NULL

rule_type
name
description NULL

status

created_at
updated_at
```

Supported `rule_type`:

```text
NUMERIC_LIMIT
DATE_VALIDITY
DOCUMENT_REQUIRED
FIELD_MATCH
REGISTRY_MATCH
BOOLEAN_CHECK
OTHER
```

`rule_code` unique.

Mọi production deterministic legal rule phải map tới:

```text
legal_requirement_id
```

Không tạo legal rule không có provenance.

Không seed production rule nếu chưa có approved legal data.

---

# 4. `compliance_rule_versions`

Một rule có nhiều executable versions.

Tối thiểu:

```text
id UUID PK
rule_id UUID NOT NULL
version_number INTEGER NOT NULL

legal_document_version_id UUID NOT NULL

condition_config JSONB NOT NULL

effective_from DATE NULL
effective_to DATE NULL

status

created_at
```

Unique:

```sql
UNIQUE(rule_id, version_number)
```

CHECK:

```text
version_number > 0
effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from
```

`condition_config` chỉ chứa cấu hình executable, ví dụ:

```text
operator
input selector
required document type
registry role
parameter references
```

Không copy legal truth vào JSON nếu đã có structured legal tables.

Rule version phải resolve về cùng legal provenance với requirement.

Nếu `legal_document_version_id` không khớp version chứa requirement:
- DB/test phải chặn.

---

# 5. Rule Version Immutability

Rule version khi:

```text
ACTIVE
SUPERSEDED
```

không được sửa executable meaning tùy ý.

Correction:

```text
create new rule version
```

Không rewrite rule history.

---

# 6. `compliance_checks`

Tenant-owned.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL

batch_id UUID NOT NULL
market_id UUID NOT NULL

created_by UUID NOT NULL

parent_check_id UUID NULL
check_number INTEGER NOT NULL

status
overall_result NULL

idempotency_key NULL

started_at NULL
completed_at NULL

failure_reason NULL

created_at
updated_at
```

Status:

```text
QUEUED
PROCESSING
COMPLETED
FAILED
CANCELLED
```

Overall result:

```text
COMPLIANT
ACTION_REQUIRED
NON_COMPLIANT
MANUAL_REVIEW_REQUIRED
```

Hai field này có ý nghĩa khác nhau:

```text
status = process state
overall_result = business conclusion
```

Composite tenant FK:

```sql
FOREIGN KEY (organization_id, batch_id)
REFERENCES export_batches (organization_id, id)
```

Re-check:

```text
new compliance_check row
parent_check_id = previous check
```

Không update check cũ thành check mới.

`parent_check_id` phải cùng organization và cùng batch.

Unique hợp lý:

```text
UNIQUE(organization_id, id)
UNIQUE(organization_id, batch_id, check_number)
```

Idempotency:

```text
UNIQUE(organization_id, idempotency_key)
WHERE idempotency_key IS NOT NULL
```

---

# 7. Preconditions cho Production Check

Database/domain model phải support policy:

Một production compliance check chỉ được sử dụng:

```text
verified document revision
+
verified structured evidence
+
approved/active legal knowledge
```

Prompt này chưa có backend service, nên:

- enforce bằng FK/status-safe references nơi practical
- document phần nào cần transaction/service validation sau này
- không tạo trigger khổng lồ để scan toàn domain

---

# 8. `compliance_check_documents`

Đây là immutable evidence snapshot.

Tối thiểu:

```text
organization_id UUID NOT NULL
check_id UUID NOT NULL
document_id UUID NOT NULL
document_revision_id UUID NOT NULL
document_file_id UUID NOT NULL

extraction_job_id UUID NULL
verification_id UUID NOT NULL

purpose NULL

document_checksum_snapshot
file_checksum_snapshot

created_at
```

PK/unique phù hợp, ví dụ:

```text
PRIMARY KEY(check_id, document_revision_id)
```

hoặc surrogate ID nếu conventions hiện tại ưu tiên.

Bắt buộc composite tenant-safe FK tới:

```text
compliance_checks
documents
document_revisions
document_files
document_verifications
document_extraction_jobs
```

Phải đảm bảo:

```text
file thuộc revision
verification thuộc revision
extraction job nếu có thuộc revision/file
```

Không cho Check Org A snapshot Document Org B.

---

# 9. Snapshot bất biến

Khi check:

```text
COMPLETED
FAILED
CANCELLED
```

theo chosen policy, ít nhất với `COMPLETED`:

```text
compliance_check_documents
```

không được UPDATE/DELETE/INSERT thêm.

Completed check phải tái lập được exact evidence đã sử dụng.

Do verified revision hiện đã immutable, không cần copy toàn bộ OCR/lab data sang JSON nếu relational references đã đủ.

Giữ checksum snapshot để kiểm chứng evidence.

Document quyết định này.

---

# 10. `compliance_check_legal_versions`

Snapshot exact law used:

```text
check_id
legal_document_version_id
created_at
```

Nếu cần tenant identifier cho consistency với pattern check child thì có thể thêm `organization_id`, dù legal knowledge là global.

Primary key:

```text
(check_id, legal_document_version_id)
```

Completed check:
- không INSERT/UPDATE/DELETE legal-version snapshot.

Không tự động chuyển historical check sang legal version mới.

---

# 11. `rule_executions`

Lưu **mọi rule execution**, kể cả PASS.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL

check_id UUID NOT NULL
rule_version_id UUID NOT NULL

status
outcome

actual_value_numeric NULL
actual_value_text NULL
actual_unit_id NULL
actual_normalized_value NULL
actual_normalized_unit_id NULL

expected_value_numeric NULL
expected_value_text NULL
expected_unit_id NULL
expected_normalized_value NULL
expected_normalized_unit_id NULL

input_reference JSONB NULL
execution_details JSONB NULL

started_at NULL
completed_at NULL

error_code NULL
error_message NULL

created_at
```

Status:

```text
PENDING
RUNNING
COMPLETED
ERROR
```

Outcome:

```text
PASS
FAIL
SKIPPED
REVIEW_REQUIRED
```

Composite tenant FK tới check.

Rule version là global reference data.

---

# 12. Numeric Deterministic Comparison

Rule Engine foundation phải support:

```text
Lab result normalized value
vs
Legal limit normalized value
```

Không so sánh raw unit strings.

Phải giữ semantics của:

```text
EXACT
LESS_THAN
LESS_THAN_LOD
LESS_THAN_LOQ
NOT_DETECTED
DETECTED_NOT_QUANTIFIED
```

Không quy `NOT_DETECTED = 0`.

Prompt này không cần viết full production rule engine service nếu chưa có application stack.

Nhưng phải:
- model đủ dữ liệu
- có SQL/test fixture chứng minh deterministic comparison cases quan trọng
- document expected future service behavior

Nếu qualifier khiến kết luận không chắc chắn:

```text
REVIEW_REQUIRED
```

thay vì đoán PASS.

---

# 13. Scope Resolution Policy

Dùng semantics Phase 05:

```text
populated fields in one scope = AND
NULL = wildcard
multiple scope rows = OR
```

Resolution order:

```text
1. effective date
2. explicit priority
3. specificity
4. legal-version applicability
```

Nếu còn tie:

```text
AMBIGUOUS_RULE
→ REVIEW_REQUIRED
```

Không chọn ngẫu nhiên một limit/rule.

Prompt này phải thêm test/query fixture chứng minh ít nhất:

- specific scope thắng wildcard scope
- inactive/out-of-date rule không được chọn
- unresolved tie trở thành review-required

Không cần tạo generic SQL framework quá phức tạp nếu service layer sau này phù hợp hơn.

---

# 14. Registry Deterministic Check Foundation

Model phải hỗ trợ rule kiểu:

```text
Batch
→ batch_registered_entities
→ registered_export_entity
→ market_entity_approval
→ validity period
→ legal provenance
```

Use case:

```text
PUC / PHC extracted from verified document
vs
entity assigned to batch
vs
market approval validity
```

Không gọi AI.

Prompt này chỉ cần:
- document resolution logic
- test fixture chứng minh valid/invalid/expired/review scenario nếu practical

Không seed production PUC/PHC approval.

---

# 15. `findings`

Prompt 06 chỉ hỗ trợ:

```text
RULE_ENGINE
MANUAL
```

AI sẽ được thêm ở Prompt 07.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL

check_id UUID NOT NULL
rule_execution_id UUID NULL

source_type

finding_type
title
description

severity
validation_status

actual_value NULL
expected_value NULL
unit_text NULL

remediation_hint NULL

created_at
```

Severity:

```text
INFO
LOW
MEDIUM
HIGH
CRITICAL
```

Validation:

```text
VALIDATED
MANUAL_REVIEW_REQUIRED
REJECTED
```

CHECK source integrity:

For `RULE_ENGINE`:

```text
rule_execution_id IS NOT NULL
```

For `MANUAL`:

```text
rule_execution_id IS NULL
```

Prompt 07 sau này sẽ ALTER schema để thêm `ai_run_id` và source `AI`.

---

# 16. `finding_citations`

Tạo:

```text
finding_citations
```

Tối thiểu:

```text
finding_id
citation_id
is_primary
created_at
```

PK:

```text
(finding_id, citation_id)
```

Validated legal finding phải có legal citation.

Ở database pure relational, việc enforce “VALIDATED requires >=1 child citation” có thể cần deferred trigger.

Được phép dùng:
- deferred constraint trigger
hoặc
- service/transaction policy + dedicated DB test helper

Chọn cách maintainable nhất và document.

Không cho legal finding validated mà không có citation.

---

# 17. Finding creation policy

Không tạo Finding cho mọi PASS.

Thông thường:

```text
PASS → rule_execution only
FAIL → finding
REVIEW_REQUIRED → finding
```

RuleExecution là full audit của rules.

Finding là business issue surfaced cho user.

Document distinction này.

---

# 18. `compliance_check_events`

Tạo timeline:

```text
id UUID PK
organization_id UUID NOT NULL
check_id UUID NOT NULL

event_type

from_status NULL
to_status NULL

actor_type
actor_user_id NULL

metadata JSONB NULL
created_at
```

Actor types:

```text
USER
SYSTEM
RULE_ENGINE
```

Prompt 07 có thể mở rộng `AI`.

Examples:

```text
CHECK_CREATED
CHECK_STARTED
RULES_RESOLVED
RULE_EXECUTED
CHECK_COMPLETED
CHECK_FAILED
RECHECK_CREATED
```

Append-only.

---

# 19. Overall Result Policy

Không để SQL seed hoặc AI quyết định tùy ý.

Document deterministic policy:

```text
Any unresolved ambiguity/manual-review condition
→ MANUAL_REVIEW_REQUIRED

Validated critical/high mandatory failure
→ NON_COMPLIANT

Fixable validated deficiency without hard failure
→ ACTION_REQUIRED

All mandatory applicable deterministic rules pass
AND no unresolved review
AND required evidence exists
→ COMPLIANT
```

Nếu exact severity-to-result policy chưa đủ business requirements:
- implement conservative baseline
- document decision
- do not invent legal meaning.

Prompt này nên có test fixtures chứng minh aggregation.

---

# 20. Completed Check Immutability

Khi check `COMPLETED`:

Không được mutate:

```text
compliance_check_documents
compliance_check_legal_versions
rule_executions
findings
finding_citations
```

Nếu correction/reassessment:

```text
create RE-CHECK
```

Không rewrite completed history.

Append-only event logs vẫn được phép nếu event thực sự xảy ra sau completion và policy cho phép.

---

# 21. Indexes

Cân nhắc:

```text
compliance_checks(organization_id, batch_id, created_at)
compliance_checks(organization_id, status)
compliance_checks(organization_id, overall_result)

compliance_check_documents(organization_id, check_id)
compliance_check_legal_versions(check_id)

compliance_rule_versions(rule_id, version_number)
compliance_rule_versions(status, effective_from, effective_to)

rule_executions(organization_id, check_id)
rule_executions(rule_version_id)
rule_executions(outcome)

findings(organization_id, check_id)
findings(severity, validation_status)

finding_citations(finding_id)

compliance_check_events(organization_id, check_id, created_at)
```

Không tạo index dư thừa.

---

# 22. Seeds

Không seed:

```text
production compliance rules
production rule versions
legal limits
findings
checks
```

Test fixtures được phép.

Không tạo fake production compliance data.

---

# 23. Tests bắt buộc

## Rule identity/version

1. Create rule with valid legal requirement.
2. Rule without requirement bị chặn.
3. Duplicate `(rule_id, version_number)` bị chặn.
4. Rule version/legal requirement provenance mismatch bị chặn.
5. Active/superseded executable version immutable.

## Compliance Check

6. Create valid check.
7. Cross-tenant batch linkage bị chặn.
8. Duplicate idempotency key bị chặn.
9. Re-check parent phải cùng tenant/batch.
10. Status và overall_result independent.

## Evidence snapshot

11. Snapshot exact verified revision/file/verification.
12. File không thuộc revision bị chặn.
13. Verification không thuộc revision bị chặn.
14. Cross-tenant evidence snapshot bị chặn.
15. Completed check snapshot không thể sửa/xóa/thêm.

## Legal snapshot

16. Check snapshots exact legal version.
17. Completed check legal snapshot immutable.
18. New legal version không thay historical snapshot.

## Rule execution

19. PASS execution persisted without finding.
20. FAIL execution can create finding.
21. Review-required execution can create manual-review finding.
22. Unit dimension mismatch bị chặn hoặc review-required theo strategy.
23. `NOT_DETECTED` không bị convert thành zero.
24. Specific scope outranks wildcard scope.
25. unresolved tie → review required.

## Finding

26. RULE_ENGINE finding requires rule_execution_id.
27. MANUAL finding requires no rule_execution_id.
28. Invalid source combination bị chặn.
29. Validated legal finding requires citation.
30. Citation resolves through exact legal provenance.

## Overall result

31. all pass → COMPLIANT fixture.
32. mandatory high/critical failure → NON_COMPLIANT fixture.
33. fixable issue → ACTION_REQUIRED fixture.
34. ambiguity/review → MANUAL_REVIEW_REQUIRED fixture.

## Immutability

35. Completed check executions/findings/citations cannot be rewritten.
36. Re-check creates new independent check while old check remains unchanged.

## Regression

37. All migrations from empty DB PASS.
38. Migration rerun PASS.
39. Phase 01–05 tests PASS.

---

# 24. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

Docs phải giải thích:

```text
Compliance Check vs Re-check
Process status vs Overall result
Document snapshot
Legal-version snapshot
Rule vs Rule Version
Rule Execution vs Finding
Finding citation requirement
Scope resolution
Deterministic numeric/registry checks
Completed-check immutability
```

ERD chỉ thêm schema thực tế.

---

# 25. Không triển khai AI/RAG

Không tạo:

```text
ai_runs
legal_chunks
legal_embeddings
```

Không gọi Gemini.

Không fake AI response.

Prompt 07 sẽ tích hợp AI + RAG sau khi deterministic engine foundation ổn định.

---

# 26. Definition of Done

Chỉ báo DONE khi:

- migrations mới chạy sạch từ empty DB
- Phase 01–05 regression tests PASS
- rule/rule-version model hoàn thành
- compliance check + re-check lineage hoàn thành
- exact verified-document snapshot hoàn thành
- exact legal-version snapshot hoàn thành
- deterministic rule executions persist được
- scope ambiguity không bị guess
- normalized measurement comparison foundation hoạt động
- deterministic registry-check foundation hoạt động
- finding source integrity được enforce
- validated legal finding có citation
- overall-result baseline được test
- completed check immutable
- docs/ERD/status updated
- không triển khai AI/RAG/Report ngoài scope
- không seed production compliance/legal values giả

---

# 27. Handoff bắt buộc

Khi hoàn tất, trả đúng format:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

TEST RESULTS:

IMPORTANT DECISIONS:

CHECK SNAPSHOT STRATEGY:

RULE RESOLUTION STRATEGY:

OVERALL RESULT STRATEGY:

FINDING / CITATION STRATEGY:

IMMUTABILITY STRATEGY:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang AI/RAG.
