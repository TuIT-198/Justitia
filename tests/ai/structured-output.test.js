import test from 'node:test';
import assert from 'node:assert/strict';
import { parseStructuredAIOutput, StructuredOutputError } from '../../src/ai/structured-output.js';

const citationA = '11111111-1111-4111-8111-111111111111';

function validOutput(overrides = {}) {
  return {
    findings: [{
      findingType: 'DOCUMENT_CONSISTENCY',
      title: 'Review evidence consistency',
      description: 'The supplied evidence needs comparison with the cited section.',
      severity: 'MEDIUM',
      citationIds: [citationA],
      confidence: 0.8,
      remediationHint: 'Review the cited evidence.',
      ...overrides
    }]
  };
}

test('strict structured output accepts the exact contract', () => {
  assert.deepEqual(parseStructuredAIOutput(validOutput()), validOutput());
});

test('malformed output is INVALID_OUTPUT', () => {
  assert.throws(() => parseStructuredAIOutput('not-json-object'), StructuredOutputError);
});

test('unknown severity is rejected', () => {
  assert.throws(() => parseStructuredAIOutput(validOutput({ severity: 'CERTAINLY_BAD' })), /severity is invalid/);
});

test('unknown fields, including authoritative overall result, are rejected', () => {
  assert.throws(
    () => parseStructuredAIOutput({ ...validOutput(), overallResult: 'COMPLIANT' }),
    /unknown field overallResult/
  );
  assert.throws(() => parseStructuredAIOutput(validOutput({ reasoning: 'hidden' })), /unknown field reasoning/);
});
