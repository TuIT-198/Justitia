import test from 'node:test';
import assert from 'node:assert/strict';
import { ReportService } from '../../src/reports/report-service.js';

test('report generation delegates to the atomic snapshot function', async () => {
  let call;
  const service = new ReportService({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [{ id: 'report-1' }] };
    }
  });
  const id = await service.generate({
    organizationId: 'org', checkId: 'check', generatedBy: 'user',
    reportCode: 'R-1', title: 'Report', executiveSummary: 'Summary'
  });
  assert.equal(id, 'report-1');
  assert.match(call.sql, /generate_compliance_report/);
  assert.deepEqual(call.params, ['org', 'check', 'user', 'R-1', 'Report', 'Summary']);
});

test('report approval workflow preserves explicit submission round and decision boundaries', async () => {
  const calls = [];
  const service = new ReportService({
    async query(sql, params) {
      calls.push({ sql, params });
      if (sql.includes('submit_compliance_report')) return { rows: [{ submission_round: 2 }] };
      return { rows: [{ decision: 'APPROVED' }] };
    }
  });
  assert.equal(await service.submit({ organizationId: 'org', reportId: 'report', actorId: 'submitter' }), 2);
  assert.equal(await service.decide({
    organizationId: 'org', reportId: 'report', reviewerId: 'manager', decision: 'APPROVED'
  }), 'APPROVED');
  assert.match(calls[1].sql, /decide_compliance_report/);
});
