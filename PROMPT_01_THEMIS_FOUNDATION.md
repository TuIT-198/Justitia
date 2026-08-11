# PROMPT 01 — KHỞI ĐỘNG DỰ ÁN & CHỐT DATABASE FOUNDATION

Bạn là Senior Solution Architect + PostgreSQL Database Architect cho dự án **Themis LexiGuard**.

## Mục tiêu của prompt này

Chỉ làm **giai đoạn đầu tiên**. Không triển khai Frontend, AI, RAG, OCR, Compliance Engine hay các module phía sau.

Mục tiêu là:
1. Kiểm tra repository hiện tại.
2. Chuẩn hóa cấu trúc project nếu cần.
3. Chốt kiến trúc database nền tảng theo hướng production-ready.
4. Chuẩn bị migrations cho phần nền móng.
5. Tạo tài liệu trạng thái để prompt tiếp theo có thể tiếp tục mà không cần đọc lại toàn bộ lịch sử chat.

---

## Bối cảnh dự án

Themis LexiGuard là hệ thống AI Compliance dành cho doanh nghiệp Việt Nam xuất khẩu nông sản.

Scope triển khai đầu tiên:
- Sản phẩm: Sầu riêng
- Xuất xứ: Việt Nam
- Thị trường chính: Trung Quốc / GACC

Hệ thống sau này phải hỗ trợ:
- Batch xuất khẩu
- Chứng từ
- OCR + human verification
- PUC/PHC
- Legal Knowledge
- Rule Engine
- AI với citation
- Compliance Check
- Report bất biến
- Remediation + Re-check
- Legal Change Monitoring
- Alerts
- Audit

Nhưng **prompt này chưa triển khai các chức năng đó**.

---

# 1. VIỆC ĐẦU TIÊN: INSPECT REPOSITORY

Đọc toàn bộ cấu trúc repository hiện tại.

Không xóa code hữu ích khi chưa hiểu mục đích.

Hãy báo cáo:
- Tech stack hiện có
- Cấu trúc folder
- Database tooling hiện có
- Docker hiện có hay chưa
- ORM/query builder nếu có
- Auth implementation nếu đã tồn tại
- Các phần có thể tái sử dụng
- Các phần xung đột với kiến trúc mới

Tạo:

```text
/docs/implementation-status.md
```

Format:

```text
# Implementation Status

## Current Phase
...

## DONE
...

## IN_PROGRESS
...

## TODO
...

## BLOCKED
...

## Important Decisions
...
```

Luôn cập nhật file này từ các prompt sau.

---

# 2. DATABASE TECHNOLOGY

Database chính:

```text
PostgreSQL
```

Quy ước:

- UUID primary key
- TIMESTAMPTZ cho timestamp
- DATE cho ngày nghiệp vụ/pháp lý
- JSONB chỉ khi thực sự cần
- INET cho IP
- snake_case
- migrations bắt buộc
- không sửa production schema bằng tay
- hỗ trợ PostgreSQL RLS
- thiết kế tenant-safe

Chưa cần pgvector ở prompt này.

---

# 3. MULTI-TENANT FOUNDATION

`organization_id` là security boundary.

Các bảng tenant-owned phải được thiết kế để ngăn liên kết chéo doanh nghiệp.

Root table nên hỗ trợ:

```sql
UNIQUE (organization_id, id)
```

Child table quan trọng sử dụng composite FK dạng:

```sql
FOREIGN KEY (organization_id, parent_id)
REFERENCES parent_table (organization_id, id)
```

Không chỉ dựa vào RLS.

RLS sẽ được triển khai sau khi schema nền ổn định, nhưng schema ngay từ đầu phải hỗ trợ chiến lược này.

---

# 4. MODULE CẦN THIẾT KẾ/TRIỂN KHAI TRONG PROMPT NÀY

Chỉ làm các nhóm sau.

## Identity

```text
users
user_credentials
email_verification_tokens
password_reset_tokens
user_sessions
```

Yêu cầu:

- email unique không phân biệt hoa thường
- user có thể có 0 hoặc 1 local credential để sau này hỗ trợ SSO
- password hash, không plaintext
- token chỉ lưu hash
- session lưu refresh token hash
- hỗ trợ revoke session
- expires_at phải hợp lệ

## Organization & RBAC

```text
organizations
organization_members
roles
permissions
role_permissions
organization_member_roles
```

MVP role hệ thống:

```text
OWNER
MANAGER
COMPLIANCE
LEGAL_SPECIALIST
STAFF
SYSTEM_ADMIN
```

Một member có thể có nhiều role.

Không đặt `role_id` trực tiếp trong `organization_members`.

Role → Permission theo N:N.

Chưa cần cho tenant tự tạo custom role.

## Reference geography

```text
countries
markets
```

Tối thiểu seed:
- Vietnam
- China
- market CN_GACC

## Product foundation

```text
products
product_varieties
product_forms
```

Seed:
- Durian
- một số form cơ bản:
  - FRESH
  - FROZEN_WHOLE
  - FROZEN_PULP
  - FROZEN_PUREE

Không tự ý seed dữ liệu pháp lý/MRL.

## HS foundation

Thiết kế:

```text
hs_nomenclatures
hs_codes
product_hs_codes
```

`hs_codes.code` không unique toàn cục.

Dùng:

```text
UNIQUE(nomenclature_id, code)
```

Mapping phải hỗ trợ:
- product
- product form
- market
- thời gian hiệu lực

Không dùng mã HS từ tài liệu demo như dữ liệu production nếu chưa được xác minh chính thức.

---

# 5. DATABASE MIGRATIONS

Nếu project chưa có migration framework, chọn giải pháp phù hợp với stack hiện tại và giải thích quyết định.

Tạo migrations có thứ tự rõ ràng, ví dụ:

```text
001_extensions
002_identity
003_organizations_rbac
004_country_market
005_products
006_hs_codes
007_seed_reference_data
```

Tên có thể thay đổi theo tooling.

Migration phải chạy sạch từ database rỗng.

---

# 6. CONSTRAINTS TỐI THIỂU

Implement ở database level khi phù hợp:

- PK
- FK
- UNIQUE
- CHECK
- composite FK
- useful indexes

Ví dụ:

```text
expires_at > created_at
```

```text
organization_members:
UNIQUE(organization_id, user_id)
```

```text
organization_member_roles:
UNIQUE(organization_member_id, role_id)
```

```text
product_varieties:
UNIQUE(product_id, code)
```

```text
product_forms:
UNIQUE(product_id, code)
```

```text
legal/document/compliance tables chưa tạo trong prompt này
```

---

# 7. DOCKER / LOCAL DATABASE

Nếu chưa có PostgreSQL local setup, bổ sung Docker Compose tối thiểu.

Phải có:

```text
.env.example
```

Không commit secret thật.

README phải ghi cách:

```text
start PostgreSQL
run migration
run seed
inspect database
reset local database
```

---

# 8. TEST DATABASE FOUNDATION

Viết test hoặc script kiểm chứng ít nhất:

1. Email duplicate bị chặn.
2. Một user có thể không có local credential.
3. Member có nhiều role.
4. Member không bị trùng trong cùng organization.
5. Product form không trùng code trong cùng product.
6. HS code có thể trùng code nếu thuộc nomenclature khác.
7. Migration chạy từ database trắng.
8. Seed chạy lại an toàn hoặc có chiến lược rõ ràng.

---

# 9. DOCUMENTATION

Cập nhật/tạo:

```text
/docs/database/schema.md
/docs/database/erd.md
/docs/implementation-status.md
```

ERD ở prompt này chỉ cần thể hiện những bảng đã triển khai.

Không vẽ các bảng tương lai như thể chúng đã tồn tại.

---

# 10. KHÔNG ĐƯỢC LÀM TRONG PROMPT NÀY

Không triển khai:

- Export Batch
- PUC/PHC
- Document upload
- Document revision
- OCR
- Lab result
- Measurement units
- Legal Knowledge
- RAG
- Compliance Rule Engine
- Gemini
- Findings
- Reports
- Remediation
- Monitoring
- Alerts
- Dashboard

Các phần trên để prompt sau.

---

# 11. DEFINITION OF DONE CHO PROMPT 01

Chỉ được báo DONE khi:

- Repository đã được inspect.
- `/docs/implementation-status.md` tồn tại.
- PostgreSQL local setup hoạt động.
- Migration framework hoạt động.
- Identity schema hoàn thành.
- Organization + RBAC schema hoàn thành.
- Country/Market schema hoàn thành.
- Product foundation hoàn thành.
- HS foundation hoàn thành.
- Constraints/indexes cần thiết có mặt.
- Reference seeds chạy được.
- Migration từ empty DB chạy thành công.
- Các test foundation pass.
- README/database docs được cập nhật.
- Không có secret bị commit.
- Không có dữ liệu pháp lý giả được seed.

Cuối cùng hãy trả về một **handoff summary ngắn**, gồm:

```text
DONE:
FILES CREATED/CHANGED:
DATABASE TABLES CREATED:
TEST RESULTS:
IMPORTANT DECISIONS:
BLOCKERS:
NEXT PROMPT SHOULD START WITH:
```

Dừng tại đó. Không tự chuyển sang phase tiếp theo.
