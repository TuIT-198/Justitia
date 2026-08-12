import test from 'node:test';
import assert from 'node:assert/strict';
import { AlertService } from '../../src/alerts/alert-service.js';
import { NotificationService } from '../../src/alerts/notification-service.js';

test('alert creation exposes the database deduplication result', async () => {
  const service = new AlertService({
    async query(sql, params) {
      assert.match(sql, /create_batch_risk_alerts/);
      assert.deepEqual(params, ['change']);
      return { rows: [{ count: '2' }] };
    }
  });
  assert.equal(await service.createForRegulationChange({ regulationChangeId: 'change' }), 2);
});

test('alert acknowledgement carries organization and acting user', async () => {
  let params;
  const service = new AlertService({
    async query(sql, values) {
      assert.match(sql, /acknowledge_alert/);
      params = values;
      return { rows: [] };
    }
  });
  await service.acknowledge({ organizationId: 'org', alertId: 'alert', userId: 'manager' });
  assert.deepEqual(params, ['org', 'alert', 'manager']);
});

test('in-app notification creation exposes its idempotent insert count', async () => {
  const service = new NotificationService({
    async query(sql, params) {
      assert.match(sql, /create_in_app_notifications_for_alert/);
      assert.deepEqual(params, ['alert']);
      return { rows: [{ count: 0 }] };
    }
  });
  assert.equal(await service.createInAppForAlert({ alertId: 'alert' }), 0);
});
