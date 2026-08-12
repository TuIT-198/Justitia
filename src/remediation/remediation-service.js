export class RemediationService {
  constructor(database) {
    this.database = database;
  }

  async createTask(input) {
    const result = await this.database.query(
      'SELECT create_remediation_task($1, $2, $3, $4, $5, $6, $7, $8) AS id',
      [input.organizationId, input.reportId, input.findingId, input.title,
        input.description ?? null, input.priority, input.dueDate ?? null, input.createdBy]
    );
    return result.rows[0].id;
  }

  async assign({ organizationId, taskId, userId, assignedBy }) {
    await this.database.query('SELECT assign_remediation_task($1, $2, $3, $4)', [
      organizationId, taskId, userId, assignedBy
    ]);
  }

  async start({ organizationId, taskId, actorId }) {
    await this.database.query('SELECT start_remediation_task($1, $2, $3)', [
      organizationId, taskId, actorId
    ]);
  }

  async submitEvidence(input) {
    const result = await this.database.query(
      'SELECT submit_remediation_evidence($1, $2, $3, $4, $5, $6, $7) AS id',
      [input.organizationId, input.taskId, input.documentId, input.revisionId,
        input.verificationId, input.submittedBy, input.description ?? null]
    );
    return result.rows[0].id;
  }

  async decideEvidence({ organizationId, evidenceId, reviewerId, decision }) {
    await this.database.query('SELECT decide_remediation_evidence($1, $2, $3, $4)', [
      organizationId, evidenceId, reviewerId, decision
    ]);
  }

  async reviewTask({ organizationId, taskId, reviewerId, decision, comment = null }) {
    const result = await this.database.query(
      'SELECT review_remediation_task($1, $2, $3, $4, $5) AS id',
      [organizationId, taskId, reviewerId, decision, comment]
    );
    return result.rows[0].id;
  }
}
