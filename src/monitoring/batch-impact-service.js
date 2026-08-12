export class BatchImpactService {
  constructor(database) {
    this.database = database;
  }

  async assess({ organizationId, batchId, changeItemId, previousCheckId = null }) {
    const result = await this.database.query(
      'SELECT assess_batch_legal_impact($1, $2, $3, $4) AS id',
      [organizationId, batchId, changeItemId, previousCheckId]
    );
    return result.rows[0].id;
  }
}
