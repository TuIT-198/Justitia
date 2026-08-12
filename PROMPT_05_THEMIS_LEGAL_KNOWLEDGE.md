# PROMPT 05 — LEGAL KNOWLEDGE + OFFICIAL PROVENANCE + LEGAL LIMITS

Bạn là Senior PostgreSQL Database Architect + Legal Knowledge Domain Architect cho dự án **Themis LexiGuard**.

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

Phase 01–04 đã hoàn thành và runtime-verified.

Trạng thái hiện tại:

- PostgreSQL 15 tested baseline.
- Identity / Organization / RBAC hoàn thành.
- Country / Market / Product / HS foundation hoàn thành.
- Export Batch + registry entity foundation hoàn thành.
- Document identity + immutable revision + private file metadata hoàn thành.
- Extraction / extracted fields / lab results / human verification hoàn thành.
- Measurement dimensions + canonical unit normalization foundation hoàn thành.
- Verified document structured evidence là immutable.
- `lab_test_results` hiện giữ `analyte_name_raw` + `analyte_name_normalized`, chưa có regulated-substance catalog.
- Chưa có Legal Knowledge, Legal Limits, Citations, Compliance Engine, AI hoặc RAG.
- Không có MRL/legal/HS/PUC/PHC production data chưa xác minh.

Không làm lại các phần đã DONE nếu không phát hiện lỗi thực sự.

---

# 1. Mục tiêu Prompt 05

Chỉ triển khai relational **Legal Knowledge foundation**:

```text
Official Source
→ Legal Authority
→ Legal Document
→ Legal Document Version
→ Official Legal File
→ Article / Clause / Point hierarchy
→ Structured Legal Requirement
→ Requirement Scope
→ Requirement Parameter
→ Regulated Substance
→ Structured Legal Limit
→ Legal Citation
→ Market Entity Approval provenance
→ Optional Lab Result ↔ Regulated Substance mapping
```

Mục tiêu quan trọng:

```text
Mọi legal rule/limit production
phải truy ngược được về
official source + exact legal version + exact legal section.
```

Không triển khai:

- Compliance Rule Engine
- rule executions
- compliance checks
- Gemini
- RAG chunks/embeddings
- reports
- remediation
- legal-change diff/monitoring
- alerts
- dashboard
- RLS
- crawler
- real legal-data automation

Dừng sau Prompt 05.

---

# 2. Nguyên tắc Legal Data bắt buộc

Đây là hệ thống legal/compliance.

Không được:

```text
- tự tạo MRL
- lấy số ví dụ trong use case làm production data
- tạo citation không có legal section thật
- ghi đè legal version cũ
- coi OCR text hoặc RAG chunk là nguồn luật gốc
```

Production legal fact phải có provenance:

```text
Legal Limit / Requirement
        ↓
Legal Requirement
        ↓
Legal Section
        ↓
Legal Document Version
        ↓
Legal Document
        ↓
Official Legal Source
```

Test fixtures có thể dùng dữ liệu giả, nhưng phải nằm trong test DB và không được seed như production reference data.

---

# 3. Tables cần tạo

Tối thiểu:

```text
legal_sources
legal_authorities

legal_documents
legal_document_parties
legal_document_versions
legal_document_files

legal_sections

legal_requirements
requirement_scopes
requirement_parameters

regulated_substances
legal_limits

legal_citations

market_entity_approvals
```

Có thể ALTER:

```text
lab_test_results
```

để bổ sung nullable FK:

```text
regulated_substance_id
```

nếu phù hợp với schema hiện tại.

Không tạo RAG tables trong prompt này.

---

# 4. `legal_sources`

Tạo:

```text
legal_sources
```

Tối thiểu:

```text
id UUID PK

name
source_type

base_url NULL
country_id NULL

is_official BOOLEAN NOT NULL
trust_level

status

created_at
updated_at
```

Supported `source_type`:

```text
GOVERNMENT_PORTAL
OFFICIAL_DATABASE
AUTHORITY_WEBSITE
TREATY_SOURCE
OFFICIAL_PUBLICATION
OTHER
```

`trust_level` tối thiểu:

```text
PRIMARY
SECONDARY
UNKNOWN
```

Production compliance data chỉ được enable từ approved/official source theo policy sau này.

Không seed URL pháp lý nếu chưa được xác minh.

---

# 5. `legal_authorities`

Tạo:

```text
legal_authorities
```

Tối thiểu:

```text
id UUID PK

country_id NULL

code NULL
name
short_name NULL

authority_type NULL
official_url NULL

status

created_at
updated_at
```

Authority là cơ quan pháp lý/quản lý, khác với `organizations` là tenant doanh nghiệp.

Ví dụ conceptual:

```text
customs authority
agriculture authority
food safety authority
treaty signatory
```

Không hard-code tên cơ quan thật nếu không có nguồn xác minh trong project.

---

# 6. `legal_documents`

Tạo:

```text
legal_documents
```

Tối thiểu:

```text
id UUID PK

source_id UUID NOT NULL

document_code NULL
title
short_title NULL

document_type
jurisdiction_type

language_code

signed_date NULL
publication_date NULL

current_status

summary NULL

created_at
updated_at
```

Supported `document_type`:

```text
LAW
DECREE
CIRCULAR
DECISION
PROTOCOL
REGULATION
STANDARD
NOTICE
GUIDELINE
OTHER
```

Supported `jurisdiction_type`:

```text
NATIONAL
BILATERAL
REGIONAL
INTERNATIONAL
```

Không lưu toàn bộ nội dung văn bản trong `legal_documents`.

---

# 7. `legal_document_parties`

Tạo:

```text
legal_document_parties
```

Tối thiểu:

```text
id UUID PK
legal_document_id UUID NOT NULL
authority_id UUID NOT NULL
party_role
created_at
```

Supported role:

```text
SIGNATORY
ISSUING_AUTHORITY
IMPLEMENTING_AUTHORITY
SUPERVISORY_AUTHORITY
OTHER
```

Unique exact relation hợp lý:

```text
legal_document_id + authority_id + party_role
```

---

# 8. `legal_document_versions`

Đây là immutable legal snapshot.

Tạo:

```text
legal_document_versions
```

Tối thiểu:

```text
id UUID PK

legal_document_id UUID NOT NULL

version_number INTEGER NOT NULL
version_label NULL

effective_from DATE NULL
effective_to DATE NULL
published_at DATE NULL

status

previous_version_id UUID NULL

change_summary NULL
content_hash NULL

created_at
```

Supported status:

```text
DRAFT
UNDER_REVIEW
APPROVED
UPCOMING
ACTIVE
SUPERSEDED
EXPIRED
REPEALED
```

Unique:

```sql
UNIQUE(legal_document_id, version_number)
```

CHECK:

```text
version_number > 0
effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from
```

`previous_version_id` phải thuộc cùng legal document.

Enforce bằng DB nếu có thể bằng composite uniqueness/FK.

---

# 9. Legal Version Immutability

Một version ở trạng thái:

```text
APPROVED
ACTIVE
SUPERSEDED
EXPIRED
REPEALED
```

không được thay đổi nội dung/provenance fields tùy ý.

Nếu có thay đổi pháp lý thật:

```text
create NEW legal_document_version
```

Cho phép lifecycle transition hợp lệ nếu cần:

```text
APPROVED → ACTIVE
ACTIVE → SUPERSEDED / EXPIRED / REPEALED
```

Nhưng không được sửa:

```text
legal_document_id
version_number
content_hash
effective provenance
```

sau khi version đã được approved/active.

Nếu dùng trigger:
- đơn giản
- test được
- không khóa transition hợp lệ

Phase Compliance sau sẽ tăng cường rule:
“version đã được completed check sử dụng thì tuyệt đối immutable”.

---

# 10. `legal_document_files`

Tạo:

```text
legal_document_files
```

Tối thiểu:

```text
id UUID PK
version_id UUID NOT NULL

file_name
mime_type

storage_provider NULL
bucket_name NULL
storage_path

language_code

checksum_sha256

is_original BOOLEAN NOT NULL DEFAULT TRUE
page_count NULL

created_at
```

Mục tiêu:

```text
Legal Version
→ exact official source file
→ SHA-256
```

Không permanent public URL.

Không overwrite original legal source file.

CHECK:

```text
page_count IS NULL OR page_count > 0
```

---

# 11. `legal_sections`

Tạo hierarchical legal structure:

```text
legal_sections
```

Tối thiểu:

```text
id UUID PK

version_id UUID NOT NULL
parent_id UUID NULL

section_type
section_number NULL
title NULL
content

order_index

page_start NULL
page_end NULL

created_at
updated_at
```

Supported types:

```text
PART
CHAPTER
SECTION
ARTICLE
CLAUSE
POINT
ANNEX
OTHER
```

Hierarchy:

```text
Document Version
→ Chapter
→ Article
→ Clause
→ Point
```

`parent_id` phải:

- thuộc cùng `version_id`
- không được cross-version parent
- không self-reference trực tiếp

Enforce same-version relationship bằng composite FK nếu có thể.

CHECK:

```text
order_index >= 0
page_start IS NULL OR page_start > 0
page_end IS NULL OR page_end > 0
page_end IS NULL OR page_start IS NULL OR page_end >= page_start
```

Không chunk ở phase này.

---

# 12. `legal_requirements`

Tạo:

```text
legal_requirements
```

Tối thiểu:

```text
id UUID PK

section_id UUID NOT NULL

requirement_code
title
requirement_text

requirement_type
obligation_level
validation_type
severity_default

priority INTEGER NOT NULL DEFAULT 0

effective_from NULL
effective_to NULL

status

created_at
updated_at
```

`requirement_code` unique theo strategy hợp lý.

Nếu global code:
```text
UNIQUE(requirement_code)
```

Nếu version-scoped code hợp lý hơn, document quyết định.

Supported `requirement_type`:

```text
FOOD_SAFETY
PHYTOSANITARY
PESTICIDE_RESIDUE
HEAVY_METAL
TEMPERATURE
PACKAGING
LABELING
REGISTRATION
GROWING_AREA
PACKING_FACILITY
TRACEABILITY
CERTIFICATE
IMPORT_INSPECTION
STORAGE
TRANSPORT
OTHER
```

Supported `obligation_level`:

```text
MUST
MUST_NOT
SHOULD
MAY
INFORMATIONAL
```

Supported `validation_type`:

```text
BOOLEAN
NUMERIC_LIMIT
DATE_VALIDITY
REFERENCE_MATCH
DOCUMENT_REQUIRED
REGISTRY_LOOKUP
MANUAL_REVIEW
OTHER
```

Status:

```text
DRAFT
UNDER_REVIEW
APPROVED
ACTIVE
SUPERSEDED
INACTIVE
```

Chỉ requirement `APPROVED/ACTIVE` mới được phase Compliance sau xem xét cho production checks.

---

# 13. Requirement Scope Semantics

Tạo:

```text
requirement_scopes
```

Tối thiểu:

```text
id UUID PK

requirement_id UUID NOT NULL

product_id UUID NULL
product_form_id UUID NULL
hs_code_id UUID NULL

origin_country_id UUID NULL
destination_country_id UUID NULL

market_id UUID NULL

priority INTEGER NOT NULL DEFAULT 0

created_at
```

Semantics bắt buộc:

## Trong một scope row

Populated dimensions kết hợp bằng:

```text
AND
```

Ví dụ:

```text
product = Durian
AND product_form = Frozen
AND market = China
```

## NULL

Trong scope:

```text
NULL = wildcard / applies to all values for that dimension
```

## Nhiều scope rows

Các scope rows của cùng requirement kết hợp bằng:

```text
OR
```

Document semantics này rõ trong `docs/database/schema.md`.

Không để NULL semantics mơ hồ.

---

# 14. Scope Consistency

Nếu `product_form_id` có giá trị:

- product form phải thuộc `product_id` nếu product_id cũng có giá trị.

Nếu `hs_code_id` có giá trị:
- phải là HS record hợp lệ.
- applicability product/form/market vẫn có thể cần domain resolution phase sau.

Không tạo fake logic chỉ để ép HS mapping.

---

# 15. Specificity / Priority

Phase này phải chuẩn bị cho deterministic rule resolution.

Khi nhiều scope cùng match, future domain logic sẽ xét:

```text
1. effective date
2. explicit priority
3. specificity
4. legal version applicability
```

Specificity được hiểu là số dimension non-NULL phù hợp.

Không cần tạo stored `specificity_score` nếu có thể tính khi query/service.

Nếu Agent chọn stored/generated field:
- giải thích
- test
- không làm khó migration

Nếu vẫn ambiguity sau resolution:
- phase Compliance phải trả `AMBIGUOUS_RULE`
- không đoán.

Document decision.

---

# 16. `requirement_parameters`

Tạo:

```text
requirement_parameters
```

Tối thiểu:

```text
id UUID PK

requirement_id UUID NOT NULL

parameter_code
operator

value_numeric NULL
value_text NULL
value_boolean NULL

min_value NULL
max_value NULL

unit_id NULL
normalized_value_numeric NULL
normalized_unit_id NULL

created_at
```

Supported operator:

```text
EQ
NE
LT
LTE
GT
GTE
BETWEEN
IN
NOT_IN
EXISTS
NOT_EXISTS
```

Không dùng unit string tự do.

Numeric parameter dùng `measurement_units`.

Normalized unit phải compatible/canonical theo dimension.

---

# 17. `regulated_substances`

Tạo:

```text
regulated_substances
```

Tối thiểu:

```text
id UUID PK

code
name

substance_type

cas_number NULL
aliases JSONB NULL

status

created_at
updated_at
```

Supported `substance_type`:

```text
PESTICIDE
HEAVY_METAL
CONTAMINANT
MICROBIOLOGICAL
OTHER
```

Không seed legal substance list production nếu chưa có verified source.

Test fixtures được phép.

---

# 18. Lab Result ↔ Regulated Substance

ALTER:

```text
lab_test_results
```

thêm nullable:

```text
regulated_substance_id UUID NULL
```

Giữ nguyên:

```text
analyte_name_raw
analyte_name_normalized
```

Không replace raw OCR name.

Ý nghĩa:

```text
OCR raw analyte
        ↓
normalized name
        ↓
review/mapping
        ↓
regulated_substance_id
```

Mapping có thể chưa tự động.

Không tạo AI matching ở phase này.

---

# 19. `legal_limits`

Tạo:

```text
legal_limits
```

Tối thiểu:

```text
id UUID PK

requirement_id UUID NOT NULL
substance_id UUID NULL

product_id UUID NULL
product_form_id UUID NULL
hs_code_id UUID NULL
market_id UUID NULL

limit_type
operator

limit_value NUMERIC NOT NULL
unit_id UUID NOT NULL

normalized_limit_value NUMERIC NOT NULL
normalized_unit_id UUID NOT NULL

priority INTEGER NOT NULL DEFAULT 0

effective_from DATE NOT NULL
effective_to DATE NULL

status

created_at
updated_at
```

Supported `limit_type`:

```text
MRL
MAX_CONTAMINANT
MINIMUM
MAXIMUM
RANGE
OTHER
```

Supported operator:

```text
LT
LTE
GT
GTE
EQ
```

Không lưu `mg/kg` string.

Dùng `measurement_units`.

Normalized unit phải:
- cùng dimension
- canonical active unit

CHECK:

```text
effective_to IS NULL OR effective_to >= effective_from
limit_value >= 0
```

Nếu một loại legal limit có thể âm trong tương lai, document exception; với MRL/contaminant thì nonnegative.

---

# 20. Legal Limit Provenance

Mọi `legal_limits` bắt buộc trỏ tới:

```text
legal_requirement
```

Requirement lại bắt buộc trỏ tới:

```text
legal_section
```

Do đó provenance chain tồn tại.

Không tạo legal limit orphan.

Không seed actual MRL/legal threshold trong production migration.

---

# 21. Overlap / Ambiguity

Không được âm thầm chọn một legal limit nếu có 2 record cùng áp dụng.

Ở phase này:

- tạo effective date constraints
- tạo indexes cần thiết
- nếu có thể implement exact-scope overlap exclusion sạch bằng PostgreSQL 15 mà không làm schema quá phức tạp, hãy làm và test
- nếu không, document rõ overlap detection sẽ được Compliance Rule Resolution phase enforce bằng query/service

Không over-engineer `COALESCE(UUID sentinel)` hack khó maintain chỉ để đạt constraint.

Correctness + maintainability ưu tiên hơn clever SQL.

---

# 22. `legal_citations`

Tạo:

```text
legal_citations
```

Tối thiểu:

```text
id UUID PK

section_id UUID NOT NULL
requirement_id UUID NULL

citation_code
display_label

quote_excerpt NULL

canonical_reference NULL

created_at
updated_at
```

Bắt buộc:

```text
section_id NOT NULL
```

Nếu `requirement_id` có giá trị:
- requirement phải thuộc chính section đó hoặc nằm trong legal relationship hợp lệ đã định nghĩa.

Enforce bằng DB nếu composite relationship hợp lý.

Citation không được chỉ là free text không truy về section.

---

# 23. `market_entity_approvals`

Bây giờ Legal dependencies đã có, tạo:

```text
market_entity_approvals
```

Mục tiêu:

```text
PUC / PHC / facility
→ approved for a market
→ by authority
→ under exact legal/source provenance
```

Tối thiểu:

```text
id UUID PK

registered_entity_id UUID NOT NULL
market_id UUID NOT NULL

authority_id UUID NOT NULL

source_version_id UUID NOT NULL
legal_citation_id UUID NOT NULL

approval_status

valid_from DATE NOT NULL
valid_to DATE NULL

created_at
updated_at
```

Supported status:

```text
APPROVED
SUSPENDED
REVOKED
EXPIRED
PENDING
```

CHECK:

```text
valid_to IS NULL OR valid_to >= valid_from
```

Không seed PUC/PHC/GACC approval production data.

---

# 24. Market Approval Provenance

Database phải đảm bảo:

```text
legal_citation_id
→ section
→ same legal document/version provenance
```

Nếu citation không trực tiếp chứa version_id, resolve qua:

```text
citation
→ section
→ version
```

Nếu `source_version_id` và citation version không khớp:
- phải bị DB constraint/trigger hoặc test/service policy chặn.

Ưu tiên relational composite FK nếu practical.

Không cho approval nói:

```text
source_version A
+
citation thuộc version B
```

---

# 25. Immutability

Bảo vệ:

```text
legal_document_versions
legal_document_files
legal_sections
legal_requirements
legal_limits
legal_citations
```

khi legal version đã ở trạng thái approved/active tùy strategy.

Không nhất thiết khóa mọi status transition.

Mục tiêu:

```text
Approved legal meaning/provenance không bị rewrite.
```

Nếu correction:
- new legal version
- new structured legal data

Document trigger/policy rõ.

---

# 26. Tenant Boundary

Legal Knowledge:

```text
global/shared reference domain
```

Không thêm `organization_id` vào:

```text
legal_sources
legal_documents
legal_sections
legal_requirements
regulated_substances
legal_limits
legal_citations
market_entity_approvals
```

trừ khi project có lý do mạnh.

Tenant data vẫn là:

```text
organization
batch
document
lab result
```

Điều này cho phép nhiều tenant dùng cùng legal source of truth.

---

# 27. Indexes

Cân nhắc ít nhất:

```text
legal_documents(source_id, document_type)
legal_document_versions(legal_document_id, status)
legal_document_versions(effective_from, effective_to)

legal_sections(version_id, order_index)
legal_sections(version_id, parent_id)

legal_requirements(section_id, status)
legal_requirements(requirement_type, validation_type)

requirement_scopes(requirement_id)
requirement_scopes(product_id, product_form_id, market_id)
requirement_scopes(hs_code_id)

regulated_substances(code)
regulated_substances(name)

legal_limits(requirement_id)
legal_limits(substance_id, product_id, market_id)
legal_limits(effective_from, effective_to)

legal_citations(section_id)
legal_citations(requirement_id)

market_entity_approvals(registered_entity_id, market_id)
market_entity_approvals(market_id, approval_status)
```

Không tạo index dư thừa nếu UNIQUE đã cover.

---

# 28. Seeds

Không seed legal production facts.

Allowed:

- enum/catalog config nếu schema dùng lookup table
- không cần real legal source
- không cần real authority
- không cần real substance
- không cần real legal limit

Use test fixtures for assertions.

Nếu project có official sample file ở local repository và người dùng đã đặt nó vào test fixture folder:
- có thể dùng metadata/file checksum làm DEVELOPMENT fixture
- không tự suy diễn legal limit/requirement nếu chưa được review/verified

---

# 29. Tests bắt buộc

Mở rộng database tests.

## Legal source/document/version

1. Create legal source.
2. Create legal document.
3. Duplicate legal document version number bị chặn.
4. Previous version cross-document bị chặn.
5. Invalid effective date range bị chặn.
6. Approved/active version immutable fields được bảo vệ.
7. New version vẫn tạo được sau version cũ.

## Sections

8. Create Article → Clause → Point hierarchy.
9. Parent section cross-version bị chặn.
10. Invalid page range bị chặn.

## Requirements/scopes

11. Requirement bắt buộc thuộc section.
12. Scope NULL semantics được documented/test fixture phản ánh.
13. Product form inconsistent với product bị chặn khi cả hai set.
14. Effective range invalid bị chặn.
15. Multiple scope rows cho same requirement được phép.

## Parameters/units

16. Numeric parameter reference valid unit.
17. Normalized unit incompatible dimension bị chặn.
18. Canonical normalized unit requirement được enforce theo chosen strategy.

## Substance/lab mapping

19. Lab result có thể map tới regulated substance.
20. Raw/normalized analyte names vẫn được giữ.
21. Invalid substance FK bị chặn.

## Legal limits

22. Legal limit bắt buộc có requirement.
23. Unit + normalized unit dimension consistency.
24. Negative invalid limit bị chặn theo chosen policy.
25. Invalid effective range bị chặn.
26. Legal limit không có source chain hợp lệ không thể tồn tại do FK chain.
27. Nếu exact-scope overlap exclusion được implement, test overlap bị chặn.

## Citations

28. Citation không có section bị chặn.
29. Requirement/citation inconsistent section bị chặn nếu enforce strategy hỗ trợ.
30. Citation truy được:
    `citation → section → version → document → source`.

## Market approvals

31. Approval có valid registry entity + market + authority + legal version + citation.
32. Citation/version mismatch bị chặn theo chosen strategy.
33. Invalid approval date range bị chặn.

## Regression

34. All migrations from empty DB PASS.
35. Migration rerun PASS.
36. Phase 01 tests PASS.
37. Phase 02 tests PASS.
38. Phase 03 tests PASS.
39. Phase 04 tests PASS.

---

# 30. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

Docs phải giải thích rõ:

```text
Official legal provenance chain
Legal document vs legal version
Legal section hierarchy
Requirement vs scope vs parameter
Legal limit vs lab result
Citation model
Market entity approval provenance
Scope NULL / AND / OR semantics
Priority/specificity strategy
Legal immutability strategy
```

ERD chỉ thêm schema thực tế đã implement.

---

# 31. Không triển khai Compliance Engine

Prompt 05 dừng trước:

```text
compliance_rules
compliance_rule_versions
compliance_checks
rule_executions
findings
finding_citations
ai_runs
```

Không tạo placeholder tables.

Prompt tiếp theo sẽ chuyển structured legal knowledge thành executable deterministic compliance rules.

---

# 32. Definition of Done

Chỉ báo DONE khi:

- migrations mới chạy sạch từ empty DB
- Phase 01–04 regression tests PASS
- official legal source model hoàn thành
- legal authority model hoàn thành
- document/version/file model hoàn thành
- section hierarchy hoàn thành
- version immutability hoạt động
- legal requirements hoàn thành
- scope semantics rõ và test được
- requirement parameters dùng normalized unit model
- regulated substance catalog foundation hoàn thành
- lab result nullable mapping tới substance hoạt động
- legal limits có normalized unit + provenance
- legal citations luôn resolve về exact section
- market entity approval có exact legal provenance
- required tests PASS
- docs/ERD/status updated
- không seed unverified legal/MRL/PUC/PHC/HS production data
- không triển khai Compliance/AI/RAG ngoài scope

---

# 33. Handoff bắt buộc

Khi hoàn tất, trả đúng format:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

TEST RESULTS:

IMPORTANT DECISIONS:

LEGAL IMMUTABILITY STRATEGY:

SCOPE RESOLUTION STRATEGY:

LEGAL PROVENANCE STRATEGY:

SUBSTANCE MAPPING STRATEGY:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang Compliance Engine.
