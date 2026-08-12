# PROMPT 02 — EXPORT BATCH + PUC/PHC REGISTRY

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

Phase 01 đã hoàn thành với:

- PostgreSQL 17
- ordered plain-SQL migrations
- `schema_migrations`
- Identity
- Organization + RBAC
- Countries / Markets
- Products / Varieties / Forms
- HS nomenclatures / HS codes / product mappings
- foundation tests đang PASS
- chưa có RLS
- chưa seed HS/MRL/legal data chưa xác minh

Không làm lại các phần đã DONE nếu không phát hiện lỗi thật.

---

# 1. Mục tiêu Prompt 02

Chỉ triển khai:

```text
Export Batch
+
Export Batch Items
+
PUC/PHC/Facility Registry Foundation
+
Organization ↔ Registered Entity
+
Batch ↔ Registered Entity
+
Tenant-safe constraints
+
Tests
+
ERD/docs/status
```

Không triển khai:

- Document upload
- Document revision
- OCR
- Lab Result
- Measurement Units
- Legal Knowledge
- Legal Citation
- Market Entity Approval có provenance pháp lý
- Compliance Engine
- AI/RAG
- Report
- Remediation
- Monitoring
- Alerts
- Dashboard
- RLS

Dừng khi hoàn tất Prompt 02.

---

# 2. Export Batch

Tạo:

```text
export_batches
export_batch_items
```

## `export_batches`

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL
batch_code
origin_country_id
destination_country_id
market_id
status
planned_export_date
actual_export_date
notes
created_by
created_at
updated_at
deleted_at
```

Yêu cầu:

```sql
UNIQUE (organization_id, batch_code)
UNIQUE (organization_id, id)
```

`organization_id` là tenant boundary.

Batch lifecycle status phải tách khỏi compliance result.

Status MVP hợp lý:

```text
DRAFT
PREPARING
READY_FOR_CHECK
UNDER_REVIEW
ACTION_REQUIRED
READY_FOR_EXPORT
EXPORTED
CANCELLED
```

Dùng CHECK constraint hoặc lookup approach phù hợp với pattern Phase 01.

Không dùng `NON_COMPLIANT` làm lifecycle status của batch.

---

# 3. Export Batch Item

`export_batch_items` phải có:

```text
id
organization_id
batch_id

product_id
variety_id nullable
product_form_id
hs_code_id nullable

quantity nullable
quantity_unit nullable
net_weight_kg nullable
lot_reference nullable

created_at
updated_at
```

Composite tenant FK bắt buộc:

```sql
FOREIGN KEY (organization_id, batch_id)
REFERENCES export_batches (organization_id, id)
```

Không cho organization A tạo batch item tham chiếu batch của B.

---

# 4. Product / Variety / Form Consistency

Database phải ngăn:

```text
product = Durian
variety = variety của product khác
```

và:

```text
product = Durian
form = form của product khác
```

Nếu Phase 01 chưa có, bổ sung:

```sql
UNIQUE (product_id, id)
```

cho:

```text
product_varieties
product_forms
```

Sau đó dùng composite FK:

```sql
FOREIGN KEY (product_id, variety_id)
REFERENCES product_varieties (product_id, id)
```

và:

```sql
FOREIGN KEY (product_id, product_form_id)
REFERENCES product_forms (product_id, id)
```

`variety_id` được phép NULL.

Ưu tiên FK/constraint hơn trigger nếu giải quyết được bằng relational integrity.

---

# 5. HS Reference

Không seed HS code mới trong Prompt 02 nếu chưa có nguồn chính thức được xác minh.

`hs_code_id` có thể nullable để batch draft vẫn được tạo trước khi classification hoàn tất.

Nếu Phase 01 đã có `product_hs_codes`, không tự động giả định mọi mapping là legally valid.

Prompt này chỉ đảm bảo batch item có thể tham chiếu một HS record hợp lệ khi record đó tồn tại.

Việc resolve:

```text
product + form + market + effective date → applicable HS
```

sẽ do domain logic ở phase sau xử lý nếu không thể enforce sạch bằng FK.

Document quyết định này.

---

# 6. Registered Export Entities

Tạo:

```text
registered_export_entities
organization_registered_entities
batch_registered_entities
```

## `registered_export_entities`

Đây là master registry entity.

Tối thiểu:

```text
id UUID PK
entity_type
registry_namespace
registry_code
name
country_id
status
metadata JSONB NULL
created_at
updated_at
```

Supported entity types:

```text
GROWING_AREA
PACKING_FACILITY
PROCESSING_FACILITY
STORAGE_FACILITY
```

Ý nghĩa MVP:

```text
GROWING_AREA     = PUC-like entity
PACKING_FACILITY = PHC-like entity
```

Không giả định `registry_code` unique toàn cầu.

Dùng uniqueness theo namespace, ví dụ:

```sql
UNIQUE (registry_namespace, registry_code)
```

Nếu bạn chọn thêm `country_id` vào uniqueness thì phải giải thích lý do trong docs.

`registry_namespace` phải có ý nghĩa rõ ràng, ví dụ cơ quan/hệ thống đăng ký hoặc namespace nội bộ chuẩn hóa; không hard-code tên cơ quan pháp lý chưa được ingest.

---

# 7. Organization ↔ Registered Entity

Tạo:

```text
organization_registered_entities
```

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL
registered_entity_id UUID NOT NULL
relationship_type
valid_from DATE NULL
valid_to DATE NULL
created_at
```

Relationship type:

```text
OWNER
CONTRACTED
SUPPLIER
AUTHORIZED_USER
```

Yêu cầu:

```text
valid_to IS NULL OR valid_to >= valid_from
```

Không làm mất lịch sử chỉ để ép một relation duy nhất.

Nếu cần chống duplicate exact row, dùng uniqueness hợp lý.

Nếu cùng organization/entity có nhiều khoảng thời gian, giữ lịch sử.

---

# 8. Batch ↔ Registered Entity

Tạo:

```text
batch_registered_entities
```

Tối thiểu:

```text
id UUID PK
organization_id UUID NOT NULL
batch_id UUID NOT NULL
registered_entity_id UUID NOT NULL
entity_role
created_at
```

Supported roles:

```text
GROWER
PACKER
PROCESSOR
STORAGE
```

Composite tenant FK bắt buộc:

```sql
FOREIGN KEY (organization_id, batch_id)
REFERENCES export_batches (organization_id, id)
```

Chống duplicate exact link bằng:

```text
UNIQUE (
  organization_id,
  batch_id,
  registered_entity_id,
  entity_role
)
```

Không ép một role chỉ có một entity.

Một batch có thể có nhiều grower/packer nếu dữ liệu nghiệp vụ sau này cần.

---

# 9. Tenant Integrity

Tất cả bảng tenant-owned mới phải mang `organization_id` nếu phù hợp.

Tối thiểu:

```text
export_batches
export_batch_items
organization_registered_entities
batch_registered_entities
```

Mục tiêu:

- tránh cross-tenant linkage ở DB level
- chuẩn bị cho RLS phase sau

Không bật RLS trong Prompt 02.

Nhưng docs phải ghi rõ bảng nào là tenant root và bảng nào là tenant child.

---

# 10. Indexes

Thêm index theo query thực tế, tối thiểu cân nhắc:

```text
export_batches(organization_id, status)
export_batches(organization_id, planned_export_date)
export_batch_items(organization_id, batch_id)

registered_export_entities(registry_namespace, registry_code)
registered_export_entities(country_id, entity_type)

organization_registered_entities(organization_id, registered_entity_id)
batch_registered_entities(organization_id, batch_id)
batch_registered_entities(registered_entity_id)
```

Không tạo index dư thừa nếu UNIQUE/FK đã sinh index tương đương theo migration strategy hiện tại.

Document index decisions ngắn gọn.

---

# 11. Tests bắt buộc

Mở rộng `tests/database`.

Phải test ít nhất:

### Batch

1. Tạo batch hợp lệ.
2. Duplicate `(organization_id, batch_code)` bị chặn.
3. Hai organization khác nhau được phép dùng cùng `batch_code`.
4. Batch item của Org A không thể tham chiếu Batch của Org B.
5. `actual_export_date`/status không cần business trigger phức tạp ở phase này nếu chưa có rule chính thức.

### Product consistency

6. Batch item không thể chọn variety thuộc product khác.
7. Batch item không thể chọn product form thuộc product khác.
8. Variety NULL vẫn hợp lệ.

### Registry

9. Duplicate `(registry_namespace, registry_code)` bị chặn.
10. Một organization có thể liên kết registry entity.
11. Invalid effective date range bị chặn.
12. Batch có thể liên kết GROWER.
13. Batch có thể liên kết PACKER.
14. Duplicate exact batch-entity-role link bị chặn.
15. Batch của Org A không thể được gắn qua `organization_id` giả sang Org B.

### Migration

16. Toàn bộ migration từ empty DB PASS.
17. Migration rerun behavior vẫn PASS theo framework hiện tại.
18. Existing Phase 01 tests không bị regression.

---

# 12. Seeds

Không cần seed registry entity giả làm production data.

Chỉ seed nếu thật sự là reference enumeration/configuration cần thiết và phù hợp với pattern Phase 01.

Không seed:

- PUC thật
- PHC thật
- GACC approval
- HS code chưa xác minh
- MRL
- legal limits

Test fixtures được phép trong test database.

---

# 13. Docs

Cập nhật:

```text
docs/database/schema.md
docs/database/erd.md
docs/implementation-status.md
README.md
```

ERD phải thêm đúng các bảng Prompt 02.

Không vẽ Document/OCR/Legal/Compliance như thể chúng đã được triển khai.

Trong `implementation-status.md`:

```text
Current Phase = Phase 02
```

Khi hoàn tất chuyển thành Complete và ghi rõ decisions.

---

# 14. Không tạo `market_entity_approvals` ở phase này

Bảng approval thị trường sau này cần provenance từ:

```text
legal_authorities
legal_document_versions
legal_citations
```

Các bảng Legal chưa tồn tại.

Vì vậy Prompt 02 chỉ xây registry identity + organization/batch linkage.

Không thêm fake legal provenance chỉ để hoàn thành bảng.

---

# 15. Definition of Done

Chỉ báo DONE khi:

- migrations mới chạy thành công từ empty DB
- Phase 01 migrations/tests vẫn PASS
- `export_batches` hoàn thành
- `export_batch_items` hoàn thành
- product/variety/form integrity được DB enforce
- registry master hoàn thành
- organization ↔ registry hoàn thành
- batch ↔ registry hoàn thành
- tenant-safe composite FKs hoạt động
- indexes cần thiết có mặt
- required tests PASS
- docs/ERD/status được cập nhật
- không seed dữ liệu pháp lý/HS/PUC/PHC không xác minh
- không triển khai phase ngoài scope

---

# 16. Handoff bắt buộc

Khi hoàn tất, trả đúng format:

```text
DONE:

FILES CREATED/CHANGED:

DATABASE TABLES CREATED:

DATABASE TABLES ALTERED:

TEST RESULTS:

IMPORTANT DECISIONS:

BLOCKERS:

NEXT PROMPT SHOULD START WITH:
- Read docs/implementation-status.md completely before implementing the next phase.
```

Sau đó STOP.

Không tự chuyển sang Document/OCR phase.
