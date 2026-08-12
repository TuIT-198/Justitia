export class LegalChangeService {
  constructor(database) {
    this.database = database;
  }

  async compare({ fromVersionId = null, toVersionId }) {
    const result = await this.database.query(
      'SELECT compare_legal_versions($1, $2) AS id',
      [fromVersionId, toVersionId]
    );
    return result.rows[0].id;
  }

  async confirm({ changeId, confirmedBy, summary = null }) {
    await this.database.query(
      'SELECT confirm_regulation_change($1, $2, $3)',
      [changeId, confirmedBy, summary]
    );
  }
}
