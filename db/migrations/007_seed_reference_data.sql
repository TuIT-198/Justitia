INSERT INTO roles (code, name, description, is_system) VALUES
    ('OWNER', 'Owner', 'Organization owner', true),
    ('MANAGER', 'Manager', 'Organization manager', true),
    ('COMPLIANCE', 'Compliance', 'Compliance operator or reviewer', true),
    ('LEGAL_SPECIALIST', 'Legal Specialist', 'Legal knowledge specialist', true),
    ('STAFF', 'Staff', 'General organization staff', true),
    ('SYSTEM_ADMIN', 'System Administrator', 'Platform administrator', true)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description;

INSERT INTO permissions (code, resource, action, description) VALUES
    ('ORGANIZATION_READ', 'organization', 'read', 'View organization details'),
    ('ORGANIZATION_MANAGE', 'organization', 'manage', 'Manage organization details'),
    ('MEMBER_READ', 'member', 'read', 'View organization members'),
    ('MEMBER_MANAGE', 'member', 'manage', 'Invite and manage members'),
    ('REFERENCE_READ', 'reference', 'read', 'View reference data'),
    ('REFERENCE_MANAGE', 'reference', 'manage', 'Manage reference data')
ON CONFLICT (code) DO UPDATE SET
    resource = EXCLUDED.resource,
    action = EXCLUDED.action,
    description = EXCLUDED.description;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.code IN ('OWNER', 'SYSTEM_ADMIN')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.code = 'MANAGER'
  AND p.code IN ('ORGANIZATION_READ', 'ORGANIZATION_MANAGE', 'MEMBER_READ', 'MEMBER_MANAGE', 'REFERENCE_READ')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.code IN ('COMPLIANCE', 'LEGAL_SPECIALIST', 'STAFF')
  AND p.code IN ('ORGANIZATION_READ', 'MEMBER_READ', 'REFERENCE_READ')
ON CONFLICT DO NOTHING;

INSERT INTO countries (iso2_code, iso3_code, name_en, name_vi) VALUES
    ('VN', 'VNM', 'Vietnam', 'Việt Nam'),
    ('CN', 'CHN', 'China', 'Trung Quốc')
ON CONFLICT (iso2_code) DO UPDATE SET
    iso3_code = EXCLUDED.iso3_code,
    name_en = EXCLUDED.name_en,
    name_vi = EXCLUDED.name_vi,
    is_active = true;

INSERT INTO markets (code, name, country_id, market_type, regulatory_label)
SELECT 'CN_GACC', 'China / GACC', id, 'EXPORT', 'GACC'
FROM countries WHERE iso2_code = 'CN'
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    country_id = EXCLUDED.country_id,
    market_type = EXCLUDED.market_type,
    regulatory_label = EXCLUDED.regulatory_label,
    status = 'ACTIVE';

INSERT INTO products (code, name_vi, name_en, scientific_name, category)
VALUES ('DURIAN', 'Sầu riêng', 'Durian', 'Durio zibethinus', 'FRUIT')
ON CONFLICT (code) DO UPDATE SET
    name_vi = EXCLUDED.name_vi,
    name_en = EXCLUDED.name_en,
    scientific_name = EXCLUDED.scientific_name,
    category = EXCLUDED.category,
    status = 'ACTIVE';

INSERT INTO product_forms (product_id, code, name_vi, name_en)
SELECT p.id, form.code, form.name_vi, form.name_en
FROM products p
CROSS JOIN (VALUES
    ('FRESH', 'Tươi', 'Fresh'),
    ('FROZEN_WHOLE', 'Đông lạnh nguyên quả', 'Frozen whole'),
    ('FROZEN_PULP', 'Cơm đông lạnh', 'Frozen pulp'),
    ('FROZEN_PUREE', 'Xay nhuyễn đông lạnh', 'Frozen puree')
) AS form(code, name_vi, name_en)
WHERE p.code = 'DURIAN'
ON CONFLICT (product_id, code) DO UPDATE SET
    name_vi = EXCLUDED.name_vi,
    name_en = EXCLUDED.name_en,
    status = 'ACTIVE';

