INSERT INTO permissions(code, resource, action, description) VALUES
    ('AUDIT_READ', 'audit', 'read', 'View tenant audit history'),
    ('SECURITY_AUDIT_ACCESS', 'security', 'audit_access', 'Review sensitive data access history')
ON CONFLICT (code) DO UPDATE SET
    resource = EXCLUDED.resource,
    action = EXCLUDED.action,
    description = EXCLUDED.description;

INSERT INTO role_permissions(role_id, permission_id)
SELECT role_record.id, permission_record.id
FROM roles role_record
CROSS JOIN permissions permission_record
WHERE role_record.code IN ('OWNER', 'SYSTEM_ADMIN')
  AND permission_record.code IN ('AUDIT_READ', 'SECURITY_AUDIT_ACCESS')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions(role_id, permission_id)
SELECT role_record.id, permission_record.id
FROM roles role_record
CROSS JOIN permissions permission_record
WHERE role_record.code = 'MANAGER'
  AND permission_record.code = 'AUDIT_READ'
ON CONFLICT DO NOTHING;
