export class CitationValidator {
  constructor(citationRepository) {
    this.citationRepository = citationRepository;
  }

  async validateFindings({ organizationId, checkId, findings, retrievedContext }) {
    const allowedByContext = new Set(retrievedContext.flatMap((chunk) => chunk.citation_ids ?? chunk.citationIds ?? []));
    const requested = [...new Set(findings.flatMap((finding) => finding.citationIds))];
    const validForCheck = new Set(await this.citationRepository.findValidForCheck({
      organizationId,
      checkId,
      citationIds: requested
    }));

    return findings.map((finding) => {
      const invalid = finding.citationIds.filter((id) => !allowedByContext.has(id) || !validForCheck.has(id));
      if (finding.citationIds.length === 0) {
        return { ...finding, validationStatus: 'MANUAL_REVIEW_REQUIRED', validationError: 'MISSING_CITATION' };
      }
      if (invalid.length > 0) {
        return {
          ...finding,
          validationStatus: 'MANUAL_REVIEW_REQUIRED',
          validationError: 'INVALID_CITATION',
          invalidCitationIds: invalid
        };
      }
      return { ...finding, validationStatus: 'VALIDATED' };
    });
  }
}
