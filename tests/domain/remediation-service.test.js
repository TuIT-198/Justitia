import test from 'node:test';
import assert from 'node:assert/strict';
import { RemediationService } from '../../src/remediation/remediation-service.js';

test('remediation evidence references an exact revision and verification', async () => {
  let call;
  const service = new RemediationService({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [{ id: 'evidence-1' }] };
    }
  });
  const id = await service.submitEvidence({
    organizationId: 'org', taskId: 'task', documentId: 'document',
    revisionId: 'revision-3', verificationId: 'verification-3', submittedBy: 'user'
  });
  assert.equal(id, 'evidence-1');
  assert.match(call.sql, /submit_remediation_evidence/);
  assert.deepEqual(call.params.slice(2, 5), ['document', 'revision-3', 'verification-3']);
});

test('remediation review uses auditable database workflow functions', async () => {
  const calls = [];
  const service = new RemediationService({
    async query(sql, params) {
      calls.push({ sql, params });
      return { rows: [{ id: 'review-1' }] };
    }
  });
  await service.decideEvidence({
    organizationId: 'org', evidenceId: 'evidence', reviewerId: 'manager', decision: 'ACCEPTED'
  });
  assert.equal(await service.reviewTask({
    organizationId: 'org', taskId: 'task', reviewerId: 'manager', decision: 'APPROVED'
  }), 'review-1');
  assert.match(calls[0].sql, /decide_remediation_evidence/);
  assert.match(calls[1].sql, /review_remediation_task/);
});
