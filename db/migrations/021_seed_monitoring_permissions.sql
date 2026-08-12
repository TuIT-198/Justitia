INSERT INTO permissions(code, resource, action, description) VALUES
    ('LEGAL_CHANGE_READ', 'legal_change', 'read', 'View structured legal changes and impacts'),
    ('LEGAL_CHANGE_MANAGE', 'legal_change', 'manage', 'Confirm structured legal changes'),
    ('ALERT_READ', 'alert', 'read', 'Receive and view tenant alerts'),
    ('ALERT_ACKNOWLEDGE', 'alert', 'acknowledge', 'Acknowledge tenant alerts')
ON CONFLICT (code) DO UPDATE SET
    resource = EXCLUDED.resource,
    action = EXCLUDED.action,
    description = EXCLUDED.description;

INSERT INTO role_permissions(role_id, permission_id)
SELECT role_record.id, permission_record.id
FROM roles role_record
CROSS JOIN permissions permission_record
WHERE role_record.code IN ('OWNER', 'MANAGER')
  AND permission_record.code IN (
      'LEGAL_CHANGE_READ', 'LEGAL_CHANGE_MANAGE',
      'ALERT_READ', 'ALERT_ACKNOWLEDGE'
  )
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions(role_id, permission_id)
SELECT role_record.id, permission_record.id
FROM roles role_record
CROSS JOIN permissions permission_record
WHERE role_record.code = 'LEGAL_SPECIALIST'
  AND permission_record.code IN ('LEGAL_CHANGE_READ', 'LEGAL_CHANGE_MANAGE')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions(role_id, permission_id)
SELECT role_record.id, permission_record.id
FROM roles role_record
CROSS JOIN permissions permission_record
WHERE role_record.code = 'COMPLIANCE'
  AND permission_record.code IN ('LEGAL_CHANGE_READ', 'ALERT_READ', 'ALERT_ACKNOWLEDGE')
ON CONFLICT DO NOTHING;
