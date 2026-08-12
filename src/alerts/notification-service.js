export class NotificationService {
  constructor(database) {
    this.database = database;
  }

  async createInAppForAlert({ alertId }) {
    const result = await this.database.query(
      'SELECT create_in_app_notifications_for_alert($1) AS count',
      [alertId]
    );
    return Number(result.rows[0].count);
  }
}
