import test from 'node:test';
import assert from 'node:assert/strict';
import { RagRetriever, RETRIEVE_LEGAL_CHUNKS_SQL } from '../../src/ai/rag-retriever.js';
import { PostgresCitationRepository, VALID_CITATIONS_FOR_CHECK_SQL } from '../../src/ai/postgres-citation-repository.js';

test('retriever delegates to the snapshot-filtered database function', async () => {
  let call;
  const retriever = new RagRetriever({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [{ chunk_id: 'chunk-1' }] };
    }
  });
  const rows = await retriever.retrieve({
    organizationId: 'org-1', checkId: 'check-1', queryEmbedding: [1, 0], embeddingModel: 'fake-v1', topK: 3
  });
  assert.match(RETRIEVE_LEGAL_CHUNKS_SQL, /retrieve_legal_chunks_for_check/);
  assert.deepEqual(call.params, ['org-1', 'check-1', '[1,0]', 'fake-v1', 3]);
  assert.deepEqual(rows, [{ chunk_id: 'chunk-1' }]);
});

test('citation repository validates through the tenant check legal snapshot', async () => {
  let call;
  const repository = new PostgresCitationRepository({
    async query(sql, params) {
      call = { sql, params };
      return { rows: [{ id: 'citation-1' }] };
    }
  });
  assert.deepEqual(await repository.findValidForCheck({
    organizationId: 'org-1', checkId: 'check-1', citationIds: ['citation-1']
  }), ['citation-1']);
  assert.match(VALID_CITATIONS_FOR_CHECK_SQL, /compliance_check_legal_versions/);
  assert.deepEqual(call.params, ['org-1', 'check-1', ['citation-1']]);
});
