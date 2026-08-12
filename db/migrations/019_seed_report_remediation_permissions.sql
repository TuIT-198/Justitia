INSERT INTO permissions(code, resource, action, description) VALUES
    ('REPORT_READ', 'report', 'read', 'View compliance reports'),
    ('REPORT_SUBMIT', 'report', 'submit', 'Generate and submit compliance reports'),
    ('REPORT_APPROVE', 'report', 'approve', 'Approve or reject compliance reports'),
    ('REMEDIATION_CREATE', 'remediation', 'create', 'Create and assign remediation work'),
    ('REMEDIATION_REVIEW', 'remediation', 'review', 'Review remediation evidence and tasks'),
    ('COMPLIANCE_RECHECK', 'compliance', 'recheck', 'Create a re-check after remediation')
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
      'REPORT_READ', 'REPORT_SUBMIT', 'REPORT_APPROVE',
      'REMEDIATION_CREATE', 'REMEDIATION_REVIEW', 'COMPLIANCE_RECHECK'
  )
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions(role_id, permission_id)
SELECT role_record.id, permission_record.id
FROM roles role_record
CROSS JOIN permissions permission_record
WHERE role_record.code = 'COMPLIANCE'
  AND permission_record.code IN ('REPORT_READ', 'REPORT_SUBMIT', 'REMEDIATION_CREATE')
ON CONFLICT DO NOTHING;
