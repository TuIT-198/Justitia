export class ReportService {
  constructor(database) {
    this.database = database;
  }

  async generate({ organizationId, checkId, generatedBy, reportCode, title, executiveSummary = null }) {
    const result = await this.database.query(
      'SELECT generate_compliance_report($1, $2, $3, $4, $5, $6) AS id',
      [organizationId, checkId, generatedBy, reportCode, title, executiveSummary]
    );
    return result.rows[0].id;
  }

  async submit({ organizationId, reportId, actorId }) {
    const result = await this.database.query(
      'SELECT submit_compliance_report($1, $2, $3) AS submission_round',
      [organizationId, reportId, actorId]
    );
    return result.rows[0].submission_round;
  }

  async decide({ organizationId, reportId, reviewerId, decision, comment = null }) {
    const result = await this.database.query(
      'SELECT decide_compliance_report($1, $2, $3, $4, $5) AS decision',
      [organizationId, reportId, reviewerId, decision, comment]
    );
    return result.rows[0].decision;
  }

  async returnRejectedToDraft({ organizationId, reportId, actorId }) {
    await this.database.query(
      'SELECT return_rejected_report_to_draft($1, $2, $3)',
      [organizationId, reportId, actorId]
    );
  }
}
