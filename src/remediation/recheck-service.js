export class RecheckService {
  constructor(database) {
    this.database = database;
  }

  async create({ organizationId, reportId, createdBy, idempotencyKey }) {
    const result = await this.database.query(
      'SELECT create_recheck_for_report($1, $2, $3, $4) AS id',
      [organizationId, reportId, createdBy, idempotencyKey]
    );
    return result.rows[0].id;
  }
}
