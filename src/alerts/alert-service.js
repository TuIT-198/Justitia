export class AlertService {
  constructor(database) {
    this.database = database;
  }

  async createForRegulationChange({ regulationChangeId }) {
    const result = await this.database.query(
      'SELECT create_batch_risk_alerts($1) AS count',
      [regulationChangeId]
    );
    return Number(result.rows[0].count);
  }

  async acknowledge({ organizationId, alertId, userId }) {
    await this.database.query(
      'SELECT acknowledge_alert($1, $2, $3)',
      [organizationId, alertId, userId]
    );
  }
}
