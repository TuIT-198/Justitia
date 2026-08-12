import test from 'node:test';
import assert from 'node:assert/strict';
import { CitationValidator } from '../../src/ai/citation-validator.js';

const citationA = '11111111-1111-4111-8111-111111111111';
const citationB = '22222222-2222-4222-8222-222222222222';
const outside = '33333333-3333-4333-8333-333333333333';
const baseFinding = { citationIds: [citationA], confidence: 0.99 };

function validator(validIds) {
  return new CitationValidator({
    async findValidForCheck() { return validIds; }
  });
}

test('existing citations allowed by context and check are validated', async () => {
  const result = await validator([citationA]).validateFindings({
    organizationId: 'org', checkId: 'check', findings: [baseFinding], citationIds: [],
    retrievedContext: [{ citation_ids: [citationA] }]
  });
  assert.equal(result[0].validationStatus, 'VALIDATED');
});

test('nonexistent or outside-snapshot citation is never silently dropped', async () => {
  const result = await validator([]).validateFindings({
    organizationId: 'org', checkId: 'check', findings: [{ ...baseFinding, citationIds: [outside] }],
    retrievedContext: [{ citation_ids: [outside] }]
  });
  assert.equal(result[0].validationStatus, 'MANUAL_REVIEW_REQUIRED');
  assert.deepEqual(result[0].invalidCitationIds, [outside]);
});

test('citation outside supplied context is rejected even if it exists in the check snapshot', async () => {
  const result = await validator([outside]).validateFindings({
    organizationId: 'org', checkId: 'check', findings: [{ ...baseFinding, citationIds: [outside] }],
    retrievedContext: [{ citation_ids: [citationA] }]
  });
  assert.equal(result[0].validationError, 'INVALID_CITATION');
});

test('empty citations require manual review regardless of confidence', async () => {
  const result = await validator([]).validateFindings({
    organizationId: 'org', checkId: 'check', findings: [{ ...baseFinding, citationIds: [] }],
    retrievedContext: []
  });
  assert.equal(result[0].validationStatus, 'MANUAL_REVIEW_REQUIRED');
  assert.equal(result[0].validationError, 'MISSING_CITATION');
});

test('multiple valid citations are preserved', async () => {
  const result = await validator([citationA, citationB]).validateFindings({
    organizationId: 'org', checkId: 'check', findings: [{ ...baseFinding, citationIds: [citationA, citationB] }],
    retrievedContext: [{ citation_ids: [citationA, citationB] }]
  });
  assert.equal(result[0].validationStatus, 'VALIDATED');
  assert.deepEqual(result[0].citationIds, [citationA, citationB]);
});
