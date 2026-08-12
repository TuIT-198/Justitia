import test from 'node:test';
import assert from 'node:assert/strict';
import { FakeAIProvider } from '../../src/ai/fake-ai-provider.js';
import { GeminiProvider, AIProviderConfigurationError } from '../../src/ai/gemini-provider.js';
import { CitationValidator } from '../../src/ai/citation-validator.js';
import { ComplianceAIService } from '../../src/ai/compliance-ai-service.js';

const citationA = '11111111-1111-4111-8111-111111111111';
const validResponse = {
  findings: [{
    findingType: 'CONTEXT_REVIEW', title: 'Review context', description: 'Review the supplied context.',
    severity: 'LOW', citationIds: [citationA], confidence: 0.7, remediationHint: 'Review evidence.'
  }]
};

function harness(response, validCitationIds = [citationA]) {
  const finalizations = [];
  const repository = {
    async isCheckCompleted() { return false; },
    async start() { return { id: 'run-1' }; },
    async finalize(value) { finalizations.push(value); }
  };
  const service = new ComplianceAIService({
    provider: new FakeAIProvider({ response }),
    retriever: { async retrieve() { return [{ citation_ids: [citationA], content: 'context' }]; } },
    citationValidator: new CitationValidator({ async findValidForCheck() { return validCitationIds; } }),
    aiRunRepository: repository
  });
  return { service, finalizations };
}

test('Gemini adapter remains explicitly blocked when secrets are absent', async () => {
  const provider = new GeminiProvider({ apiKey: '', model: '' });
  await assert.rejects(() => provider.generateStructuredAnalysis({ context: {} }), AIProviderConfigurationError);
});

test('Gemini adapter returns provider JSON through the shared contract boundary', async () => {
  let request;
  const provider = new GeminiProvider({
    apiKey: 'test-only-key',
    model: 'test-only-model',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        async json() {
          return { candidates: [{ content: { parts: [{ text: JSON.stringify(validResponse) }] } }] };
        }
      };
    }
  });
  assert.deepEqual(await provider.generateStructuredAnalysis({ context: { allowedCitationIds: [citationA] } }), validResponse);
  assert.match(request.url, /generativelanguage\.googleapis\.com/);
  assert.equal(request.options.headers['x-goog-api-key'], 'test-only-key');
});

test('valid provider output completes with validated cited findings', async () => {
  const { service, finalizations } = harness(validResponse);
  const result = await service.analyze({ organizationId: 'org', checkId: 'check' });
  assert.equal(result.status, 'COMPLETED');
  assert.equal(result.findings[0].validationStatus, 'VALIDATED');
  assert.equal(finalizations[0].status, 'COMPLETED');
});

test('invalid output records INVALID_OUTPUT and creates no findings', async () => {
  const { service, finalizations } = harness({ findings: [], overallResult: 'COMPLIANT' });
  const result = await service.analyze({ organizationId: 'org', checkId: 'check' });
  assert.equal(result.status, 'INVALID_OUTPUT');
  assert.deepEqual(result.findings, []);
  assert.deepEqual(finalizations[0].findings, []);
});

test('invalid citations take the safe manual-review path', async () => {
  const { service } = harness(validResponse, []);
  const result = await service.analyze({ organizationId: 'org', checkId: 'check' });
  assert.equal(result.findings[0].validationStatus, 'MANUAL_REVIEW_REQUIRED');
});

test('completed check analysis is refused before a provider call', async () => {
  const service = new ComplianceAIService({
    provider: new FakeAIProvider({ response: validResponse }),
    retriever: { async retrieve() { return []; } },
    citationValidator: new CitationValidator({ async findValidForCheck() { return []; } }),
    aiRunRepository: { async isCheckCompleted() { return true; } }
  });
  await assert.rejects(() => service.analyze({ organizationId: 'org', checkId: 'check' }), /Completed checks/);
});
