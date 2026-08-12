export class AuditService {
  constructor(database) {
    this.database = database;
  }

  async record({
    organizationId = null,
    userId,
    category,
    action,
    result,
    source,
    entityType = null,
    entityId = null,
    requestId = null,
    traceId = null,
    ipAddress = null,
    userAgent = null,
    metadata = null
  }) {
    const response = await this.database.query(
      `SELECT record_audit_event(
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13
      ) AS id`,
      [
        organizationId, userId, category, action, result, source,
        entityType, entityId, requestId, traceId, ipAddress, userAgent, metadata
      ]
    );
    return response.rows[0].id;
  }

  async recordChange({ auditLogId, fieldName, oldValue = null, newValue = null }) {
    const response = await this.database.query(
      'SELECT record_audit_log_change($1, $2, $3, $4) AS id',
      [auditLogId, fieldName, oldValue, newValue]
    );
    return response.rows[0].id;
  }
}
