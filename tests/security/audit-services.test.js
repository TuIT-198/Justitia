import test from 'node:test';
import assert from 'node:assert/strict';
import { AuditService } from '../../src/audit/audit-service.js';
import { DataAccessAuditService } from '../../src/audit/data-access-audit-service.js';

test('audit service records an event through the approved database function', async () => {
  let call;
  const service = new AuditService({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [{ id: 'audit-1' }] };
    }
  });
  const id = await service.record({
    organizationId: 'org', userId: 'user', category: 'REPORT',
    action: 'REPORT_APPROVED', result: 'SUCCESS', source: 'API',
    entityType: 'COMPLIANCE_REPORT', entityId: 'report'
  });
  assert.equal(id, 'audit-1');
  assert.match(call.sql, /record_audit_event/);
  assert.deepEqual(call.params.slice(0, 8), [
    'org', 'user', 'REPORT', 'REPORT_APPROVED', 'SUCCESS', 'API',
    'COMPLIANCE_REPORT', 'report'
  ]);
});

test('audit field changes stay separate from the audit event', async () => {
  let params;
  const service = new AuditService({
    async query(sql, values) {
      assert.match(sql, /record_audit_log_change/);
      params = values;
      return { rows: [{ id: 'change-1' }] };
    }
  });
  assert.equal(await service.recordChange({
    auditLogId: 'audit-1', fieldName: 'status', oldValue: 'DRAFT', newValue: 'APPROVED'
  }), 'change-1');
  assert.deepEqual(params, ['audit-1', 'status', 'DRAFT', 'APPROVED']);
});

test('sensitive data access uses the dedicated append-only path', async () => {
  let params;
  const service = new DataAccessAuditService({
    async query(sql, values) {
      assert.match(sql, /record_data_access/);
      params = values;
      return { rows: [{ id: 'access-1' }] };
    }
  });
  assert.equal(await service.record({
    organizationId: 'org', userId: 'user', resourceType: 'DOCUMENT_FILE',
    resourceId: 'file', accessType: 'DOWNLOAD', requestId: 'request'
  }), 'access-1');
  assert.deepEqual(params, ['org', 'user', 'DOCUMENT_FILE', 'file', 'DOWNLOAD', 'request', null]);
});
