const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SEVERITIES = new Set(['INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL']);
const ROOT_KEYS = new Set(['findings']);
const FINDING_KEYS = new Set([
  'findingType', 'title', 'description', 'severity',
  'citationIds', 'confidence', 'remediationHint'
]);

export class StructuredOutputError extends Error {
  constructor(message) {
    super(message);
    this.code = 'INVALID_OUTPUT';
  }
}

function assertExactKeys(value, allowed, location) {
  const keys = Object.keys(value);
  const unknown = keys.find((key) => !allowed.has(key));
  const missing = [...allowed].find((key) => !Object.hasOwn(value, key));
  if (unknown) throw new StructuredOutputError(`${location} contains unknown field ${unknown}`);
  if (missing) throw new StructuredOutputError(`${location} is missing field ${missing}`);
}

function requireNonEmptyString(value, location) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new StructuredOutputError(`${location} must be a non-empty string`);
  }
  return value.trim();
}

export function parseStructuredAIOutput(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new StructuredOutputError('AI output must be an object');
  }
  assertExactKeys(value, ROOT_KEYS, 'AI output');
  if (!Array.isArray(value.findings)) throw new StructuredOutputError('findings must be an array');

  const findings = value.findings.map((finding, index) => {
    const location = `findings[${index}]`;
    if (!finding || typeof finding !== 'object' || Array.isArray(finding)) {
      throw new StructuredOutputError(`${location} must be an object`);
    }
    assertExactKeys(finding, FINDING_KEYS, location);
    if (!SEVERITIES.has(finding.severity)) {
      throw new StructuredOutputError(`${location}.severity is invalid`);
    }
    if (!Array.isArray(finding.citationIds)
        || finding.citationIds.some((id) => typeof id !== 'string' || !UUID_PATTERN.test(id))) {
      throw new StructuredOutputError(`${location}.citationIds must contain UUIDs only`);
    }
    if (new Set(finding.citationIds).size !== finding.citationIds.length) {
      throw new StructuredOutputError(`${location}.citationIds must not contain duplicates`);
    }
    if (typeof finding.confidence !== 'number'
        || !Number.isFinite(finding.confidence)
        || finding.confidence < 0
        || finding.confidence > 1) {
      throw new StructuredOutputError(`${location}.confidence must be between 0 and 1`);
    }
    return {
      findingType: requireNonEmptyString(finding.findingType, `${location}.findingType`),
      title: requireNonEmptyString(finding.title, `${location}.title`),
      description: requireNonEmptyString(finding.description, `${location}.description`),
      severity: finding.severity,
      citationIds: [...finding.citationIds],
      confidence: finding.confidence,
      remediationHint: requireNonEmptyString(finding.remediationHint, `${location}.remediationHint`)
    };
  });
  return { findings };
}
