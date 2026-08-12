export const RETRIEVE_LEGAL_CHUNKS_SQL = `
  SELECT chunk_id, section_id, legal_document_version_id, content, citation_ids, score
  FROM retrieve_legal_chunks_for_check($1, $2, $3::vector, $4, $5)
`;

export class RagRetriever {
  constructor(database) {
    this.database = database;
  }

  async retrieve({ organizationId, checkId, queryEmbedding, embeddingModel, topK = 10 }) {
    const vectorLiteral = `[${queryEmbedding.join(',')}]`;
    const result = await this.database.query(RETRIEVE_LEGAL_CHUNKS_SQL, [
      organizationId, checkId, vectorLiteral, embeddingModel, topK
    ]);
    return result.rows;
  }
}
