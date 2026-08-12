# PROMPT 04 — OCR + HUMAN VERIFICATION + LAB RESULTS + MEASUREMENT UNITS

Bạn là Senior PostgreSQL Database Architect + Backend Domain Architect cho dự án **Themis LexiGuard**.

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
.env.example
```

Phase 01–03 đã hoàn thành.

Trạng thái hiện tại:

- PostgreSQL 15 tested baseline.
- Identity / Organization / RBAC hoàn thành.
- Country / Market / Product / HS foundation hoàn thành.
- Export Batch + PUC/PHC registry foundation hoàn thành.
- Document identity + immutable revisions + private file metadata hoàn thành.
- Verified/superseded revisions được bảo vệ bằng PostgreSQL triggers.
- File của verified revision không thể thêm/sửa/xóa.
- `batch_documents` gắn document identity, không gắn revision.
- Chưa có OCR, extraction, lab result, measurement units, legal, compliance, AI.
- Không có dữ liệu pháp lý/HS/PUC/PHC production chưa xác minh.

Không làm lại các phần đã DONE nếu không có lỗi thật.

---

# 1. Mục tiêu Prompt 04

Chỉ triển khai:

```text
Document Revision
→ Extraction Job
→ Extracted Fields
→ Lab Test Results
→ Measurement Unit Normalization
→ Human Verification
→ Verification Correction History
→ Tenant-safe constraints
→ Tests
→ Docs / ERD / status
```

Không triển khai:

- Legal Knowledge
- Legal limits / MRL
- Compliance Rule Engine
- Gemini / RAG
- Reports
- Remediation
- Monitoring
- Alerts
- Dashboard
- RLS
- Real OCR provider SDK nếu backend app chưa tồn tại

Dừng sau Prompt 04.

---

# 2. Tables cần tạo

Tối thiểu:

```text
measurement_dimensions
measurement_units

document_extraction_jobs
extracted_fields
lab_test_results

document_verifications
document_verification_changes
```

Không tạo legal tables trong prompt này.

---

# 3. Measurement Dimensions

Tạo:

```text
measurement_dimensions
```

Tối thiểu:

```text
id UUID PK
code
name
description NULL
canonical_unit_id NULL
created_at
updated_at
```

Seed reference data tối thiểu:

```text
MASS_FRACTION
MASS
TEMPERATURE
TIME
```

Có thể thêm dimension khác nếu thật sự cần cho schema.

`code` unique, case-insensitive nếu pattern hiện tại hỗ trợ.

---

# 4. Measurement Units

Tạo:

```text
measurement_units
```

Tối thiểu:

```text
id UUID PK
dimension_id UUID NOT NULL

code
symbol

conversion_factor NUMERIC NOT NULL
conversion_offset NUMERIC NOT NULL DEFAULT 0

is_canonical BOOLEAN NOT NULL DEFAULT FALSE
is_active BOOLEAN NOT NULL DEFAULT TRUE

created_at
updated_at
```

Ý nghĩa normalization:

```text
normalized_value =
raw_value * conversion_factor + conversion_offset
```

Chỉ dùng công thức trên nếu phù hợp với dimension/unit.

Seed tối thiểu các unit reference an toàn:

```text
MASS_FRACTION:
- mg/kg
- ppm
- ug/kg hoặc µg/kg với một canonical code chuẩn hóa

MASS:
- kg
- g

TEMPERATURE:
- C
- K nếu muốn support conversion offset

TIME:
- second
- minute
- hour
```

Không seed legal limits.

Yêu cầu:

- `code` unique
- mỗi unit thuộc đúng một dimension
- mỗi dimension chỉ có một canonical unit active

Nếu cần trigger/partial unique index để enforce canonical uniqueness thì được phép.

---

# 5. Document Extraction Jobs

Tạo:

```text
document_extraction_jobs
```

Tenant-owned.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL

document_revision_id UUID NOT NULL
document_file_id UUID NOT NULL

status
extraction_method

provider NULL
model_name NULL

raw_text NULL
raw_output JSONB NULL
confidence_score NULL

idempotency_key NULL
attempt_number
max_attempts
next_retry_at NULL
last_error_code NULL
error_message NULL

started_at NULL
completed_at NULL
created_at
updated_at
```

Supported `extraction_method`:

```text
OCR
VISION_LLM
PARSER
MANUAL
```

Supported status:

```text
QUEUED
PROCESSING
COMPLETED
FAILED
NEEDS_REVIEW
CANCELLED
```

Composite tenant FKs bắt buộc tới:

```text
document_revisions
document_files
```

Bảo đảm file được chọn thực sự thuộc revision được chọn.

Nếu schema hiện tại chưa thể enforce bằng một FK đơn, bổ sung composite uniqueness cần thiết rồi dùng composite FK.

Không cho extraction job của Org A tham chiếu revision/file Org B.

---

# 6. Idempotency / Retry

`idempotency_key` nên có unique phù hợp theo tenant hoặc revision context.

Không tạo duplicate processing job ngoài ý muốn.

Ví dụ:

```text
UNIQUE(organization_id, idempotency_key)
WHERE idempotency_key IS NOT NULL
```

Nếu PostgreSQL syntax/pattern hiện tại phù hợp.

CHECK:

```text
attempt_number >= 1
max_attempts >= 1
attempt_number <= max_attempts
confidence_score IS NULL OR confidence_score BETWEEN 0 AND 1
```

---

# 7. Extracted Fields

Tạo:

```text
extracted_fields
```

Tenant-owned.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL
extraction_job_id UUID NOT NULL

field_code
field_label NULL

raw_value NULL
normalized_value NULL

data_type

confidence_score NULL

page_number NULL
source_text NULL
bounding_box JSONB NULL

created_at
```

Supported `data_type`:

```text
TEXT
NUMBER
DATE
BOOLEAN
CODE
```

Ví dụ field:

```text
PUC_CODE
PHC_CODE
DOCUMENT_NUMBER
ISSUE_DATE
EXPIRY_DATE
EXPORTER_NAME
FACILITY_CODE
```

Không hard-code toàn bộ field_code bằng enum nếu cần mở rộng.

Giữ:

```text
raw_value
```

và:

```text
normalized_value
```

riêng.

Không overwrite raw OCR evidence.

---

# 8. Lab Test Results

Tạo:

```text
lab_test_results
```

Tenant-owned.

Prompt này chưa có `regulated_substances` vì Legal Knowledge chưa làm.

Vì vậy lưu analyte theo cách trung gian, ví dụ:

```text
id UUID PK
organization_id UUID NOT NULL

document_revision_id UUID NOT NULL
extraction_job_id UUID NULL

analyte_name_raw
analyte_name_normalized NULL

result_value NUMERIC NULL
result_text NULL

result_qualifier

unit_id UUID NULL
normalized_value NUMERIC NULL
normalized_unit_id UUID NULL

detection_limit NUMERIC NULL
quantification_limit NUMERIC NULL

test_method NULL
confidence_score NULL
page_number NULL

created_at
```

Sau này Legal phase sẽ bổ sung mapping tới:

```text
regulated_substances
```

Không tạo fake substance catalog ngay trong Prompt 04.

---

# 9. Result Qualifiers

Bắt buộc support:

```text
EXACT
LESS_THAN
LESS_THAN_LOD
LESS_THAN_LOQ
NOT_DETECTED
DETECTED_NOT_QUANTIFIED
TEXT_ONLY
```

Không biến:

```text
ND
```

thành `0`.

Không giả định `<0.01` có nghĩa bằng `0.01`.

Giữ semantics bằng qualifier + threshold/value.

CHECK logic hợp lý:

- EXACT thường cần `result_value`
- NOT_DETECTED có thể không có result_value
- LESS_THAN cần threshold numeric phù hợp
- LOD/LOQ phải không âm

Không cần over-engineer mọi lab convention ở phase này; document các cases chưa hỗ trợ.

---

# 10. Unit Normalization

Khi `unit_id` và numeric result tồn tại:

- cho phép lưu `normalized_value`
- `normalized_unit_id` phải thuộc cùng dimension
- normalized unit nên là canonical unit của dimension

Không bắt DB tự tính mọi conversion nếu trigger làm phức tạp hệ thống.

Có thể:
- DB enforce relational compatibility
- service phase sau tính conversion

Nhưng cần test một utility SQL/function nếu bạn chọn triển khai normalization ở DB.

Document rõ quyết định:

```text
DB-enforced
vs
application-calculated
```

Không so sánh unit string tự do.

---

# 11. Document Verification

Tạo:

```text
document_verifications
```

Tenant-owned.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL

document_revision_id UUID NOT NULL
extraction_job_id UUID NULL

status

verified_by UUID NULL

review_notes NULL

verified_at NULL
created_at
updated_at
```

Supported status:

```text
PENDING
NEEDS_REVIEW
VERIFIED
REJECTED
```

Một verification phải thuộc đúng revision và đúng tenant.

Nếu `extraction_job_id` có giá trị:
- extraction job phải thuộc cùng revision
- cùng organization

Enforce bằng composite FK nếu hợp lý.

---

# 12. Verification và Revision Status

Khi verification đạt:

```text
VERIFIED
```

revision tương ứng mới được chuyển sang:

```text
document_revisions.status = VERIFIED
```

Không cần tạo full application workflow nếu backend chưa tồn tại, nhưng DB design phải support flow này.

Nếu dùng trigger/function để đồng bộ:
- phải deterministic
- phải test
- không phá immutability triggers từ Phase 03

Nếu không tự động đồng bộ ở DB:
- document rõ rằng application transaction sau này phải cập nhật verification + revision atomic.

Ưu tiên tránh trigger phức tạp chồng chéo.

---

# 13. Verification Changes

Tạo:

```text
document_verification_changes
```

Tenant-owned.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL

verification_id UUID NOT NULL

target_type
target_id UUID NULL
field_code NULL

old_value NULL
new_value NULL
change_reason NULL

changed_by UUID NOT NULL
changed_at TIMESTAMPTZ NOT NULL
```

Supported target examples:

```text
EXTRACTED_FIELD
LAB_TEST_RESULT
MANUAL_FIELD
```

Mục tiêu:

```text
OCR đọc PUC sai
→ reviewer sửa
→ old/new values được lưu
→ audit/reproducibility giữ được
```

Không overwrite correction history.

---

# 14. Human-verified data immutability

Sau khi document revision trở thành VERIFIED:

- extraction raw history vẫn giữ nguyên
- verification change history vẫn giữ nguyên
- không cho sửa verified structured data tùy ý

Nếu cần sửa sau verification:

```text
create new document revision
→ new extraction/verification cycle
```

Do Phase 03 đã có immutability trigger trên verified revision/files, Prompt 04 phải mở rộng nguyên tắc đó tới dữ liệu structured liên quan.

Cân nhắc trigger để chặn UPDATE/DELETE lên:

```text
extracted_fields
lab_test_results
document_verifications
document_verification_changes
```

khi parent revision đã VERIFIED/SUPERSEDED.

Không được làm cho workflow review trước verification bị khóa.

---

# 15. Tenant-safe constraints

Các bảng mới tenant-owned:

```text
document_extraction_jobs
extracted_fields
lab_test_results
document_verifications
document_verification_changes
```

đều phải có `organization_id`.

Dùng composite FK để chống cross-tenant references.

RLS vẫn deferred.

---

# 16. Indexes

Cân nhắc ít nhất:

```text
document_extraction_jobs(organization_id, document_revision_id)
document_extraction_jobs(organization_id, status)

extracted_fields(organization_id, extraction_job_id)
extracted_fields(organization_id, field_code)

lab_test_results(organization_id, document_revision_id)
lab_test_results(organization_id, analyte_name_normalized)

document_verifications(organization_id, document_revision_id)
document_verifications(organization_id, status)

document_verification_changes(organization_id, verification_id)
```

Không tạo index trùng unnecessary.

---

# 17. Seeds

Seed reference/config only:

```text
measurement_dimensions
measurement_units
```

Không seed:

- lab report giả production
- analytes legal
- MRL
- contaminants limits
- PUC/PHC data
- legal rules

Test fixtures được phép trong test DB.

---

# 18. Tests bắt buộc

Mở rộng database test suite.

## Measurement

1. Unit thuộc đúng dimension.
2. Duplicate unit code bị chặn.
3. Chỉ một canonical unit active mỗi dimension.
4. Invalid conversion factor/config bị chặn nếu constraint áp dụng.

## Extraction jobs

5. Create valid extraction job.
6. Cross-tenant revision/file linkage bị chặn.
7. File không thuộc revision tương ứng bị chặn.
8. Invalid confidence bị chặn.
9. Invalid retry counters bị chặn.
10. Duplicate idempotency key bị chặn theo chosen scope.

## Extracted fields

11. Valid extracted field được tạo.
12. Cross-tenant job linkage bị chặn.
13. Raw và normalized value có thể khác nhau mà vẫn giữ cả hai.

## Lab

14. EXACT result hợp lệ.
15. NOT_DETECTED không bị ép thành zero.
16. LESS_THAN/LOD/LOQ cases hợp lệ.
17. Negative LOD/LOQ bị chặn.
18. Unit reference hợp lệ.
19. Cross-tenant revision/job linkage bị chặn.

## Verification

20. Create pending verification.
21. Cross-tenant verification linkage bị chặn.
22. Verification correction history lưu old/new value.
23. Sau revision VERIFIED, structured evidence không thể bị sửa/xóa trái phép.
24. New revision vẫn có thể có extraction + verification riêng.

## Regression

25. All migrations from empty DB PASS.
26. Migration rerun PASS.
27. Phase 01 tests PASS.
28. Phase 02 tests PASS.
29. Phase 03 tests PASS.

---

# 19. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

Docs phải giải thích:

```text
Raw OCR data
vs
Normalized structured data
vs
Human verification
```

và:

```text
Lab result qualifier semantics
```

và:

```text
Unit normalization strategy
```

ERD chỉ thêm các bảng thật sự được triển khai.

---

# 20. Không tích hợp OCR provider thật

Nếu project vẫn chưa có Backend app:

- không cài OCR SDK
- không gọi Gemini/Vision
- không fake API
- chỉ tạo database/domain foundation

Provider integration sẽ làm khi Backend/worker phase bắt đầu.

---

# 21. Definition of Done

Chỉ báo DONE khi:

- migrations mới chạy từ empty DB
- Phase 01–03 regression tests PASS
- measurement dimensions/units hoàn thành
- extraction jobs hoàn thành
- extracted fields hoàn thành
- lab result model hoàn thành
- qualifiers giữ đúng semantics
- unit normalization strategy rõ ràng
- human verification hoàn thành
- correction history hoàn thành
- tenant-safe FKs hoạt động
- verified structured data immutable
- docs/ERD/status updated
- không triển khai Legal/Compliance/AI ngoài scope
- không seed legal/MRL data giả

---

# 22. Handoff bắt buộc

Khi hoàn tất, trả đúng format:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

TEST RESULTS:

IMPORTANT DECISIONS:

UNIT NORMALIZATION STRATEGY:

VERIFICATION / IMMUTABILITY STRATEGY:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang Legal Knowledge phase.
