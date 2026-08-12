# PROMPT 07 — AI + RAG + CITATION VALIDATION

Bạn là Senior AI/RAG Engineer + Backend Architect + PostgreSQL Architect cho **Themis LexiGuard**.

## 0. Bắt buộc

Đọc hoàn toàn:

```text
docs/implementation-status.md
```

Sau đó inspect:

```text
db/migrations/
tests/database/
docs/database/
README.md
.env.example
```

Phase 01–06 đã hoàn thành. Hiện đã có immutable evidence, Legal Knowledge, deterministic Compliance Engine, findings/citations và completed-check immutability.

Không sửa phase cũ nếu không có lỗi thật.

## 1. Scope của Prompt 07

Chỉ làm:

```text
legal_sections
→ legal_chunks
→ legal_embeddings
→ RAG retrieval

compliance_check
→ ai_run
→ structured AI output
→ citationIds validation
→ AI finding
→ finding_citations
```

Không làm:

- Report
- Remediation
- Monitoring/Alerts
- Dashboard
- Frontend
- RLS hardening
- crawler production

Dừng sau phase này.

## 2. Database

Tạo:

```text
legal_chunks
legal_embeddings
ai_runs
```

ALTER `findings` để hỗ trợ:

```text
ai_run_id
source_type = AI
```

### `legal_chunks`

Tối thiểu:

```text
id UUID PK
section_id UUID NOT NULL
chunk_index INTEGER NOT NULL
content TEXT NOT NULL
token_count INTEGER NULL
content_hash TEXT NULL
metadata JSONB NULL
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

Constraint:

```text
UNIQUE(section_id, chunk_index)
chunk_index >= 0
```

Chunk phải luôn truy được:

```text
chunk → legal_section → legal_version → legal_document → legal_source
```

Không cite chunk như nguồn luật cuối cùng.

### Chunking strategy

Nguồn chunk là `legal_sections.content`, không phải raw PDF cắt mù.

Ưu tiên giữ boundary:

```text
ARTICLE
CLAUSE
POINT
ANNEX
```

Section dài có thể chia nhiều chunk, nhưng mọi chunk vẫn giữ `section_id`.

## 3. pgvector + embeddings

Nếu pgvector chưa bật, thêm migration extension phù hợp PostgreSQL 15.

Tạo:

```text
legal_embeddings
```

Tối thiểu:

```text
id UUID PK
chunk_id UUID NOT NULL
embedding VECTOR(...)
embedding_model TEXT NOT NULL
embedding_dimension INTEGER NOT NULL
content_hash TEXT NOT NULL
created_at TIMESTAMPTZ
```

Unique:

```text
UNIQUE(chunk_id, embedding_model)
```

Không hard-code dimension sai model.

Nếu chưa có secret/provider thật, automated tests dùng deterministic fake vectors.

Không fake production success.

## 4. RAG retrieval constraint

Retrieval cho một Compliance Check bắt buộc chỉ dùng legal versions đã snapshot trong:

```text
compliance_check_legal_versions
```

Tức là:

```text
query
→ vector search
→ FILTER legal_document_version_id IN check legal snapshot
→ top-k legal chunks
```

Không được lấy luật phiên bản mới/khác snapshot rồi dùng để kết luận check lịch sử.

Retriever output nên có:

```text
chunk_id
section_id
legal_document_version_id
content
citation_ids[]
score
```

Nếu chunk không có citation phù hợp, không được dùng để tạo validated legal finding.

## 5. `ai_runs`

Tenant-owned:

```text
id UUID PK
organization_id UUID NOT NULL
check_id UUID NOT NULL

provider
model_name
prompt_version
status

input_context_hash
input_snapshot JSONB NULL
raw_response JSONB NULL
validated_response JSONB NULL

confidence_score NULL

idempotency_key NULL
attempt_number
max_attempts
next_retry_at NULL

started_at NULL
completed_at NULL
last_error_code NULL
error_message NULL

created_at
updated_at
```

Status:

```text
QUEUED
PROCESSING
COMPLETED
FAILED
INVALID_OUTPUT
CANCELLED
```

Composite tenant-safe FK tới `compliance_checks`.

Enforce:

```text
confidence NULL hoặc 0..1
attempt_number >= 1
max_attempts >= 1
attempt_number <= max_attempts
```

Idempotency unique theo organization khi key không NULL.

## 6. AI provider abstraction

Preferred provider:

```text
Gemini
```

Nếu backend chưa tồn tại, tạo tối thiểu module/service foundation cần cho phase này.

Không dựng frontend.

Business layer không được gọi Gemini SDK trực tiếp khắp nơi.

Dùng abstraction kiểu:

```text
AIProvider
├── GeminiProvider
└── FakeAIProvider (tests only)
```

Nếu thiếu `GEMINI_API_KEY`:

- adapter thật vẫn được implement
- tests dùng fake provider
- `.env.example` có placeholder
- ghi blocker nếu cần real integration test
- không commit secret

## 7. Structured AI output

Nếu TypeScript, dùng Zod strict validation.

Output tối thiểu:

```text
findings: [
  {
    findingType,
    title,
    description,
    severity,
    citationIds[],
    confidence,
    remediationHint
  }
]
```

Không dùng arbitrary prose làm production result.

Malformed output:

```text
ai_runs.status = INVALID_OUTPUT
```

và không tạo validated legal finding.

## 8. AI finding integrity

Sau ALTER, final finding sources:

```text
RULE_ENGINE
AI
MANUAL
```

CHECK bắt buộc:

```text
RULE_ENGINE:
  rule_execution_id NOT NULL
  ai_run_id NULL

AI:
  ai_run_id NOT NULL
  rule_execution_id NULL

MANUAL:
  rule_execution_id NULL
  ai_run_id NULL
```

AI finding phải cùng:

```text
organization_id
check_id
```

với `ai_run`.

Enforce bằng composite FK nếu practical.

## 9. Citation validation

AI chỉ được trả `citationIds[]` từ context đã cung cấp.

Backend phải validate từng citation:

```text
citation exists
→ section exists
→ section belongs to legal version
→ legal version exists in compliance_check_legal_versions
→ citation valid for current check
```

Nếu citation invalid/nonexistent/outside snapshot:

```text
không VALIDATED
→ MANUAL_REVIEW_REQUIRED hoặc reject finding
```

Không silently bỏ citation lỗi rồi vẫn validate finding.

### No-citation rule

AI legal finding có:

```text
citationIds = []
```

không bao giờ được trở thành:

```text
VALIDATED
```

Confidence cao không phải ngoại lệ.

## 10. AI không quyết định Overall Result

Gemini không được authoritative set:

```text
COMPLIANT
ACTION_REQUIRED
NON_COMPLIANT
MANUAL_REVIEW_REQUIRED
```

Overall result vẫn do backend/domain aggregation từ deterministic executions + validated findings.

Nếu model trả field overall result ngoài schema:
- reject hoặc ignore theo strict contract
- không persist nó như business truth

## 11. Prompt/context safety

AI input chỉ chứa dữ liệu cần thiết:

```text
batch/check context
verified evidence snapshot
deterministic execution summary
retrieved legal context
allowed citation IDs
```

Không gửi:

- secret
- dữ liệu organization khác
- unrelated documents
- hidden chain-of-thought

Persist:

```text
provider
model
prompt_version
input hash/snapshot
structured response
validation result
errors
```

Không lưu chain-of-thought.

## 12. Lifecycle + immutability

MVP flow:

```text
check PROCESSING
→ deterministic rules
→ AI contextual analysis
→ citation validation
→ aggregate
→ check COMPLETED
```

Không thêm AI finding mới vào completed historical check.

Nếu cần phân tích lại:
- re-check/new analysis flow
- không rewrite history

Terminal `ai_runs` không được sửa provider/model/prompt/input/response tùy ý.

## 13. Tests bắt buộc

Test ít nhất:

### RAG
1. Chunk phải có legal section.
2. Duplicate `(section_id, chunk_index)` bị chặn.
3. Embedding phải có valid chunk.
4. Duplicate chunk/model embedding bị chặn.
5. Retrieval chỉ trả legal version thuộc check snapshot.
6. Legal version ngoài snapshot bị loại.

### AI runs
7. Valid same-tenant AI run tạo được.
8. Cross-tenant check linkage bị chặn.
9. Invalid confidence bị chặn.
10. Duplicate idempotency key bị chặn.
11. Terminal AI run immutable.

### Structured output
12. Valid output accepted.
13. Malformed output → INVALID_OUTPUT.
14. Unknown severity/schema field invalid bị reject theo strict schema.

### Citation
15. Existing allowed citation accepted.
16. Nonexistent citation rejected.
17. Citation ngoài check legal snapshot rejected.
18. Empty citation list không thể tạo validated AI legal finding.
19. Multiple valid citations supported.

### Finding source
20. AI requires `ai_run_id`.
21. AI prohibits `rule_execution_id`.
22. RULE_ENGINE prohibits `ai_run_id`.
23. MANUAL has neither.
24. Cross-check/cross-tenant AI finding bị chặn.

### Safety
25. AI cannot authoritatively set overall result.
26. Invalid AI output follows safe failure/manual-review path.
27. Missing/invalid citation never creates silent COMPLIANT conclusion.

### Regression
28. All migrations from empty DB PASS.
29. Migration rerun PASS.
30. Phase 01–06 tests PASS.
31. Nếu có backend TypeScript: typecheck + unit tests PASS.

## 14. Environment

Nếu Gemini adapter được tạo, cập nhật `.env.example`:

```text
AI_PROVIDER=gemini
GEMINI_API_KEY=
GEMINI_MODEL=
```

Embedding config thêm khi cần.

Không commit real secret.

## 15. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

Nếu có backend AI module, tạo:

```text
docs/ai/rag-and-compliance-ai.md
```

Giải thích:

```text
RAG chunk != legal citation
snapshot-filtered retrieval
provider abstraction
strict structured output
citation validation
AI source integrity
no-citation policy
AI cannot set overall result
AI run auditability
```

## 16. Không làm Report

Không tạo:

```text
compliance_reports
report_findings
report_finding_citations
report_approvals
remediation_*
```

Prompt tiếp theo mới làm Report + Remediation + Re-check workflow.

## 17. Definition of Done

Chỉ báo DONE khi:

- RAG chunk/embedding schema hoàn thành.
- pgvector hoạt động nếu được dùng.
- Retrieval bị giới hạn đúng legal snapshot.
- `ai_runs` hoàn thành.
- AI provider abstraction hoạt động hoặc adapter thật chỉ blocked bởi secret.
- Structured output strict validation hoạt động.
- AI finding source constraint hoạt động.
- citation IDs được validate.
- Missing/invalid citation không thể thành validated legal finding.
- AI không thể set authoritative overall result.
- AI history immutable/auditable.
- Phase 01–06 regression tests PASS.
- Phase 07 tests PASS.
- Docs/status updated.
- Không làm Report/Remediation ngoài scope.
- Không seed fake production AI/legal data.
- Không commit secrets.

## 18. Handoff bắt buộc

Khi hoàn tất, trả:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

BACKEND / AI COMPONENTS CREATED:

TEST RESULTS:

IMPORTANT DECISIONS:

RAG RETRIEVAL STRATEGY:

AI PROVIDER STRATEGY:

CITATION VALIDATION STRATEGY:

AI FAILURE SAFETY STRATEGY:

IMMUTABILITY STRATEGY:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang Report/Remediation.
