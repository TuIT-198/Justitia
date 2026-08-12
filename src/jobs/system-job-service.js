export class SystemJobService {
  constructor(database) {
    this.database = database;
  }

  async create({
    jobType,
    jobKey = null,
    organizationId = null,
    idempotencyKey = null,
    maxAttempts = 3,
    metadata = null
  }) {
    const response = await this.database.query(
      `INSERT INTO system_job_runs(
        job_type, job_key, organization_id, idempotency_key, max_attempts, metadata
      ) VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING id`,
      [jobType, jobKey, organizationId, idempotencyKey, maxAttempts, metadata]
    );
    return response.rows[0].id;
  }
}
