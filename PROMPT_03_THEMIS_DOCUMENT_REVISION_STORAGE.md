# PROMPT 03 — DOCUMENT + IMMUTABLE REVISION + PRIVATE STORAGE FOUNDATION

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
compose.yaml
README.md
```

Phase 01 và Phase 02 đã hoàn thành.

Trạng thái hiện tại:

- PostgreSQL 15 là tested baseline.
- ordered plain-SQL migrations.
- `schema_migrations`.
- Identity / Organization / RBAC.
- Countries / Markets.
- Products / Varieties / Forms.
- HS nomenclature / HS codes / product mappings.
- Export batches / batch items.
- Registry entity foundation.
- Organization ↔ registry entity.
- Batch ↔ registry entity.
- Tenant-safe composite FK đã bắt đầu được áp dụng.
- Chưa có RLS.
- Chưa có Document/OCR/Legal/Compliance.
- Không có HS, PUC, PHC, MRL hoặc legal production data chưa xác minh.

Không làm lại các phần đã DONE nếu không có lỗi thực sự.

---

# 1. Mục tiêu Prompt 03

Chỉ triển khai foundation cho:

```text
Document
+
Immutable Document Revision
+
Private File Metadata
+
Batch ↔ Document
+
Replacement / Revision lineage
+
Tenant-safe integrity
+
Tests
+
Docs / ERD / status
```

Prompt này **chưa triển khai OCR hoặc Lab Result**.

Không triển khai:

- OCR / extraction
- extracted fields
- lab test results
- measurement units
- legal knowledge
- legal citations
- compliance engine
- Gemini / RAG
- reports
- remediation
- monitoring
- alerts
- dashboard
- RLS

Dừng sau khi Document + Revision + Storage foundation hoàn tất.

---

# 2. Kiến trúc Document bắt buộc

Thiết kế theo nguyên tắc:

```text
DOCUMENT
   │
   ├── REVISION 1
   │      └── FILE(S)
   │
   ├── REVISION 2
   │      └── FILE(S)
   │
   └── ...
```

## Ý nghĩa

`documents` = identity nghiệp vụ ổn định của chứng từ.

`document_revisions` = trạng thái nội dung theo từng revision.

`document_files` = file vật lý thuộc một revision.

Không update nội dung của một revision đã VERIFIED.

Nếu có chứng từ mới/corrected official evidence:

- tạo revision mới nếu vẫn là cùng document identity
- hoặc tạo document mới có relationship thay thế nếu đó là một chứng từ nghiệp vụ mới

Không overwrite file cũ.

---

# 3. Tables cần tạo

Tối thiểu:

```text
document_types
documents
document_revisions
document_files
batch_documents
```

Nếu cần thêm một bảng relationship/replacement nhỏ để giữ đúng business semantics thì được phép, nhưng phải giải thích.

Không tạo OCR tables trong prompt này.

---

# 4. `document_types`

Tạo catalog:

```text
id
code
name_vi
name_en
requires_ocr
requires_verification
is_active
created_at
updated_at
```

Seed tối thiểu các loại reference/configuration:

```text
PHYTOSANITARY_CERTIFICATE
LAB_REPORT
PUC_REGISTRATION
PHC_REGISTRATION
```

Có thể thêm:

```text
PACKING_LIST
COMMERCIAL_INVOICE
CERTIFICATE_OF_ORIGIN
```

chỉ nếu cần cho schema/reference và không chứa dữ liệu pháp lý giả.

Unique:

```text
code
```

Seed phải idempotent.

---

# 5. `documents`

Đây là tenant-owned stable business identity.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL
document_type_id UUID NOT NULL

document_number NULL
title NULL

issue_date DATE NULL
expiry_date DATE NULL
issuing_organization NULL

status
created_by

created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
deleted_at TIMESTAMPTZ NULL
```

Yêu cầu:

```sql
UNIQUE (organization_id, id)
```

Không lưu file path trực tiếp trong `documents`.

Không lưu OCR data trực tiếp trong `documents`.

Document status chỉ phản ánh identity/workflow mức document, không thay thế revision status.

Nếu dùng status, giữ scope đơn giản, ví dụ:

```text
ACTIVE
SUPERSEDED
ARCHIVED
```

Không dùng `VERIFIED` ở document identity nếu verification thực chất thuộc revision.

---

# 6. `document_revisions`

Đây là phần quan trọng nhất.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL
document_id UUID NOT NULL

revision_number INTEGER NOT NULL

previous_revision_id UUID NULL

status

content_checksum NULL

created_by
created_at
verified_at NULL
superseded_at NULL
```

Composite tenant FK bắt buộc:

```sql
FOREIGN KEY (organization_id, document_id)
REFERENCES documents (organization_id, id)
```

Root/index support:

```sql
UNIQUE (organization_id, id)
```

Version uniqueness:

```sql
UNIQUE (document_id, revision_number)
```

Nếu muốn tenant-aware explicit:

```sql
UNIQUE (organization_id, document_id, revision_number)
```

Status tối thiểu:

```text
DRAFT
READY_FOR_REVIEW
VERIFIED
REJECTED
SUPERSEDED
```

## Immutable rule

Khi revision = `VERIFIED`:

- không cho sửa content identity fields của revision
- không cho đổi file membership theo cách làm thay đổi bằng chứng lịch sử
- không cho overwrite checksum
- nếu cần correction → tạo revision mới

Có thể dùng trigger để bảo vệ immutable state, nhưng trigger phải:
- đơn giản
- test được
- không cản các transition hợp lệ như VERIFIED → SUPERSEDED nếu business cho phép

Document revision history phải giữ được:

```text
Revision 1
  ↓
Revision 2
  ↓
Revision 3
```

`previous_revision_id` phải thuộc cùng organization + cùng document.

Enforce bằng DB nếu có thể.

---

# 7. `document_files`

File thuộc revision, không chỉ thuộc document.

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL
document_revision_id UUID NOT NULL

storage_provider
bucket_name
storage_path

original_file_name
mime_type
file_size_bytes
checksum_sha256

page_count NULL

uploaded_by
uploaded_at

is_original BOOLEAN
```

Composite tenant FK:

```sql
FOREIGN KEY (organization_id, document_revision_id)
REFERENCES document_revisions (organization_id, id)
```

Yêu cầu:

- Không permanent public URL.
- Không lưu secret signed URL.
- `storage_path` là private object path.
- `checksum_sha256` bắt buộc cho original evidence files nếu file đã thực sự upload.
- Không overwrite row/file cũ để thay nội dung verified revision.

Nếu backend/storage integration chưa tồn tại, prompt này chỉ cần database + storage abstraction documentation/folder preparation, không cần triển khai SDK upload thực tế.

---

# 8. Private Storage Model

Preferred conceptual provider:

```text
Supabase Storage private bucket
```

Nhưng project chưa có app/backend stack.

Vì vậy trong Prompt 03:

- Không thêm dependency runtime chỉ để upload file.
- Chỉ thiết kế metadata đúng.
- Cập nhật `.env.example` nếu cần placeholder:

```text
STORAGE_PROVIDER=
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_PRIVATE_BUCKET=
```

Chỉ thêm nếu hợp lý và không làm hỏng foundation.

Không commit key thật.

Docs phải giải thích:

```text
authorized backend
→ verifies tenant permission
→ generates short-lived signed URL
→ client accesses private file
```

Không cho FE tự tạo arbitrary signed URL.

---

# 9. `batch_documents`

Một document có thể được gắn với batch.

Tạo:

```text
batch_documents
```

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL
batch_id UUID NOT NULL
document_id UUID NOT NULL

purpose NULL
is_required BOOLEAN DEFAULT FALSE

attached_by
attached_at
```

Composite tenant FKs bắt buộc:

```sql
FOREIGN KEY (organization_id, batch_id)
REFERENCES export_batches (organization_id, id)
```

và:

```sql
FOREIGN KEY (organization_id, document_id)
REFERENCES documents (organization_id, id)
```

Không cho:

```text
Batch Org A
→ Document Org B
```

Unique exact attachment hợp lý:

```text
UNIQUE(organization_id, batch_id, document_id)
```

Không gắn revision trực tiếp vào `batch_documents`.

Lý do:

```text
batch_documents
= document identity attached to batch
```

Revision cụ thể dùng trong Compliance Check sẽ được snapshot ở phase Compliance sau.

---

# 10. Replacement / Supersession semantics

Cần hỗ trợ tình huống:

```text
Phytosanitary cũ
→ Phytosanitary cấp lại
```

Không được overwrite document cũ.

Chọn một trong hai cách:

### Cách A — cùng document identity, revision mới

Dùng khi business coi đây là cùng một document được revised/corrected.

### Cách B — document mới thay document cũ

Dùng khi đây là chứng từ chính thức mới với document number/issue date khác.

Nếu hỗ trợ cách B, có thể thêm self-reference trong `documents`:

```text
supersedes_document_id NULL
```

Nhưng phải tenant-safe.

Document quyết định rõ:

```text
revision vs replacement
```

để phase Remediation sau sử dụng đúng.

---

# 11. Check constraints

Tối thiểu:

```text
revision_number > 0
```

```text
file_size_bytes >= 0
```

```text
page_count IS NULL OR page_count > 0
```

```text
expiry_date IS NULL
OR issue_date IS NULL
OR expiry_date >= issue_date
```

`verified_at` chỉ hợp lệ khi status tương ứng.

Không cần trigger business quá phức tạp nếu test/application phase sau sẽ đảm nhiệm.

---

# 12. Tenant Integrity

Các bảng tenant-owned mới:

```text
documents
document_revisions
document_files
batch_documents
```

đều phải có `organization_id`.

Composite FKs phải ngăn cross-tenant association.

RLS vẫn deferred.

Docs phải cập nhật tenant root/child mapping.

---

# 13. Indexes

Cân nhắc ít nhất:

```text
documents(organization_id, document_type_id)
documents(organization_id, document_number)
documents(organization_id, status)

document_revisions(organization_id, document_id, revision_number)
document_revisions(organization_id, status)

document_files(organization_id, document_revision_id)

batch_documents(organization_id, batch_id)
batch_documents(organization_id, document_id)
```

Không tạo index trùng với UNIQUE index không cần thiết.

---

# 14. Tests bắt buộc

Mở rộng database tests.

Phải test tối thiểu:

## Documents

1. Create valid document.
2. Same document number không cần globally unique nếu business chưa quy định.
3. Org A document không thể được gắn sang Org B batch.
4. Issue/expiry invalid range bị chặn.

## Revisions

5. Create revision 1.
6. Duplicate revision number trong cùng document bị chặn.
7. Same revision number ở document khác được phép.
8. Previous revision phải hợp lệ.
9. Cross-tenant revision linkage bị chặn.
10. Verified revision immutability được enforce.
11. New revision có thể được tạo sau verified revision.

## Files

12. File gắn đúng revision.
13. Cross-tenant file → revision linkage bị chặn.
14. Invalid file_size/page_count bị chặn.
15. File metadata giữ checksum/path private.

## Batch documents

16. Attach document to batch cùng tenant.
17. Duplicate exact attachment bị chặn.
18. Cross-tenant batch/document attachment bị chặn.

## Regression

19. All migrations từ empty DB PASS.
20. Migration rerun PASS theo framework hiện tại.
21. Phase 01 tests PASS.
22. Phase 02 tests PASS.

---

# 15. Không tạo OCR tables

Prompt 03 dừng trước:

```text
document_extraction_jobs
extracted_fields
lab_test_results
document_verifications
```

Những bảng đó sẽ được Prompt 04 thiết kế dựa trên revision model vừa hoàn tất.

Không thêm placeholder tables.

---

# 16. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

ERD chỉ thể hiện schema thực tế đã có.

Trong docs phải giải thích rõ:

```text
Document Identity
vs
Document Revision
vs
Document File
```

và:

```text
Revision
vs
Replacement Document
```

---

# 17. Definition of Done

Chỉ báo DONE khi:

- migrations mới chạy từ empty DB
- migrations cũ không regression
- document types tồn tại
- document identity model hoàn thành
- immutable revision model hoàn thành
- file metadata model hoàn thành
- private storage approach được documented
- batch-document tenant-safe linkage hoàn thành
- verified revision không thể bị chỉnh sửa trái phép
- new revision vẫn tạo được
- all required database tests PASS
- ERD/docs/status updated
- không triển khai OCR/Legal/Compliance ngoài scope
- không có secret thật
- không có legal data giả

---

# 18. Handoff bắt buộc

Khi hoàn tất, trả đúng format:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

TEST RESULTS:

IMPORTANT DECISIONS:

IMMUTABILITY STRATEGY:

STORAGE STRATEGY:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang OCR/Lab phase.
