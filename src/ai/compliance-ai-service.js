import { parseStructuredAIOutput, StructuredOutputError } from './structured-output.js';

export class ComplianceAIService {
  constructor({ provider, retriever, citationValidator, aiRunRepository }) {
    this.provider = provider;
    this.retriever = retriever;
    this.citationValidator = citationValidator;
    this.aiRunRepository = aiRunRepository;
  }

  async analyze(request) {
    if (await this.aiRunRepository.isCheckCompleted(request.organizationId, request.checkId)) {
      throw new Error('Completed checks cannot accept AI analysis');
    }

    const retrievedContext = await this.retriever.retrieve(request);
    const inputSnapshot = {
      checkContext: request.checkContext,
      deterministicExecutionSummary: request.deterministicExecutionSummary,
      retrievedLegalContext: retrievedContext,
      allowedCitationIds: [...new Set(retrievedContext.flatMap((chunk) => chunk.citation_ids ?? chunk.citationIds ?? []))]
    };
    const run = await this.aiRunRepository.start({ ...request, inputSnapshot, retrievedContext });

    let rawResponse;
    try {
      rawResponse = await this.provider.generateStructuredAnalysis({ context: inputSnapshot });
    } catch (error) {
      await this.aiRunRepository.finalize({
        runId: run.id,
        status: 'FAILED',
        lastErrorCode: 'PROVIDER_ERROR',
        errorMessage: error.message,
        findings: []
      });
      return { runId: run.id, status: 'FAILED', findings: [] };
    }

    let validatedResponse;
    try {
      validatedResponse = parseStructuredAIOutput(rawResponse);
    } catch (error) {
      if (!(error instanceof StructuredOutputError)) throw error;
      await this.aiRunRepository.finalize({
        runId: run.id,
        status: 'INVALID_OUTPUT',
        rawResponse,
        lastErrorCode: 'INVALID_OUTPUT',
        errorMessage: error.message,
        findings: []
      });
      return { runId: run.id, status: 'INVALID_OUTPUT', findings: [] };
    }

    const findings = await this.citationValidator.validateFindings({
      organizationId: request.organizationId,
      checkId: request.checkId,
      findings: validatedResponse.findings,
      retrievedContext
    });
    await this.aiRunRepository.finalize({
      runId: run.id,
      status: 'COMPLETED',
      rawResponse,
      validatedResponse,
      confidenceScore: findings.length ? Math.min(...findings.map((finding) => finding.confidence)) : null,
      findings
    });
    return { runId: run.id, status: 'COMPLETED', findings };
  }
}
