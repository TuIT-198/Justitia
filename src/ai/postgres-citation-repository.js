export const VALID_CITATIONS_FOR_CHECK_SQL = `
  SELECT citation.id
  FROM legal_citations citation
  JOIN legal_sections section_record
    ON section_record.id = citation.section_id
   AND section_record.version_id = citation.version_id
  JOIN compliance_check_legal_versions snapshot
    ON snapshot.legal_document_version_id = section_record.version_id
  JOIN compliance_checks check_record
    ON check_record.organization_id = snapshot.organization_id
   AND check_record.id = snapshot.check_id
  WHERE check_record.organization_id = $1
    AND check_record.id = $2
    AND citation.id = ANY($3::uuid[])
`;

export class PostgresCitationRepository {
  constructor(database) {
    this.database = database;
  }

  async findValidForCheck({ organizationId, checkId, citationIds }) {
    if (citationIds.length === 0) return [];
    const result = await this.database.query(VALID_CITATIONS_FOR_CHECK_SQL, [
      organizationId, checkId, citationIds
    ]);
    return result.rows.map((row) => row.id);
  }
}
