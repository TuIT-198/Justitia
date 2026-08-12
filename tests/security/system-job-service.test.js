import test from 'node:test';
import assert from 'node:assert/strict';
import { SystemJobService } from '../../src/jobs/system-job-service.js';

test('system job creation carries tenant, retry, and idempotency context', async () => {
  let call;
  const service = new SystemJobService({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [{ id: 'job-1' }] };
    }
  });
  const id = await service.create({
    jobType: 'LEGAL_CHANGE_IMPACT_SCAN', jobKey: 'change-1',
    organizationId: 'org', idempotencyKey: 'impact-scan-1',
    maxAttempts: 5, metadata: { changeId: 'change-1' }
  });
  assert.equal(id, 'job-1');
  assert.match(call.sql, /INSERT INTO system_job_runs/);
  assert.deepEqual(call.params, [
    'LEGAL_CHANGE_IMPACT_SCAN', 'change-1', 'org', 'impact-scan-1', 5,
    { changeId: 'change-1' }
  ]);
});
