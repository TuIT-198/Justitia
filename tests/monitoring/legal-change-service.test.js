import test from 'node:test';
import assert from 'node:assert/strict';
import { LegalChangeService } from '../../src/monitoring/legal-change-service.js';

test('legal change comparison supports an amendment and a first version', async () => {
  const calls = [];
  const service = new LegalChangeService({
    async query(sql, params) {
      calls.push({ sql, params });
      return { rows: [{ id: `change-${calls.length}` }] };
    }
  });

  assert.equal(await service.compare({ fromVersionId: 'v1', toVersionId: 'v2' }), 'change-1');
  assert.equal(await service.compare({ toVersionId: 'v1' }), 'change-2');
  assert.match(calls[0].sql, /compare_legal_versions/);
  assert.deepEqual(calls.map((call) => call.params), [['v1', 'v2'], [null, 'v1']]);
});

test('legal change confirmation delegates explicit reviewer evidence', async () => {
  let call;
  const service = new LegalChangeService({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [] };
    }
  });
  await service.confirm({ changeId: 'change', confirmedBy: 'legal-user', summary: 'Reviewed' });
  assert.match(call.sql, /confirm_regulation_change/);
  assert.deepEqual(call.params, ['change', 'legal-user', 'Reviewed']);
});
