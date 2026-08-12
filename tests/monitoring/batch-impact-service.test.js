import test from 'node:test';
import assert from 'node:assert/strict';
import { BatchImpactService } from '../../src/monitoring/batch-impact-service.js';

test('batch impact assessment preserves tenant and prior-check context', async () => {
  let call;
  const service = new BatchImpactService({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [{ id: 'impact-1' }] };
    }
  });
  const id = await service.assess({
    organizationId: 'org', batchId: 'batch', changeItemId: 'item', previousCheckId: 'check'
  });
  assert.equal(id, 'impact-1');
  assert.match(call.sql, /assess_batch_legal_impact/);
  assert.deepEqual(call.params, ['org', 'batch', 'item', 'check']);
});
