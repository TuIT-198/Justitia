export class DataAccessAuditService {
  constructor(database) {
    this.database = database;
  }

  async record({
    organizationId,
    userId,
    resourceType,
    resourceId,
    accessType,
    requestId = null,
    ipAddress = null
  }) {
    const response = await this.database.query(
      'SELECT record_data_access($1, $2, $3, $4, $5, $6, $7) AS id',
      [organizationId, userId, resourceType, resourceId, accessType, requestId, ipAddress]
    );
    return response.rows[0].id;
  }
}
