import test from 'node:test';
import assert from 'node:assert/strict';
import { RecheckService } from '../../src/remediation/recheck-service.js';

test('re-check creation delegates to a new-check transaction and supplies idempotency', async () => {
  let call;
  const service = new RecheckService({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [{ id: 'check-2' }] };
    }
  });
  assert.equal(await service.create({
    organizationId: 'org', reportId: 'report-1', createdBy: 'manager', idempotencyKey: 'recheck-2'
  }), 'check-2');
  assert.match(call.sql, /create_recheck_for_report/);
  assert.deepEqual(call.params, ['org', 'report-1', 'manager', 'recheck-2']);
});
