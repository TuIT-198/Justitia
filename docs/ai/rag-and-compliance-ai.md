# RAG and Compliance AI

## Trust boundary

`legal_chunks` are retrieval artifacts derived from exact spans of `legal_sections.content`. A chunk can help select context, but it is never a legal authority. Final provenance remains:

```text
finding -> finding_citations -> legal_citation -> legal_section
        -> legal_document_version -> legal_document -> legal_source
```

No production legal record, citation, vector, or AI conclusion is seeded by Phase 07.

## Snapshot-filtered retrieval

The application calls `retrieve_legal_chunks_for_check(organization, check, query_vector, model, top_k)`. PostgreSQL first joins the tenant/check to `compliance_check_legal_versions`, then finds sections, chunks, and model-compatible embeddings inside those exact versions. Only then does it calculate cosine similarity.

The result contains chunk, section, legal version, content, section citation IDs, and score. A later legal version outside the historical check snapshot cannot enter the result. The MVP uses exact search because embedding dimensions/models are not yet production-configured; an ANN index should be added only for a verified model/dimension workload.

## Provider abstraction

Business orchestration depends on `AIProvider`, not a provider SDK. `GeminiProvider` owns the HTTP boundary and requires `GEMINI_API_KEY` plus `GEMINI_MODEL`; `FakeAIProvider` is test-only. The real adapter is implemented but no live request is reported as successful without a secret.

The service input is limited to the check context, verified/deterministic summaries supplied by its caller, retrieved legal context, and the allowed citation IDs. Secrets, unrelated tenant data, and hidden chain-of-thought are not part of the persisted contract.

## Strict output and failure safety

The accepted root object contains only `findings`. Each finding must contain exactly:

```text
findingType, title, description, severity,
citationIds, confidence, remediationHint
```

Unknown/missing fields, invalid types, invalid severities, duplicate/non-UUID citation IDs, or an AI-authored `overallResult` cause `INVALID_OUTPUT`. The raw response and error are auditable, and no findings are created. Provider transport failure uses `FAILED`, also with no findings.

## Citation validation

Every returned citation ID must satisfy both checks:

1. It was present in the retrieved context actually supplied to the model.
2. It resolves through its exact section/version to `compliance_check_legal_versions` for the same organization and check.

An empty, nonexistent, out-of-context, or outside-snapshot citation set is never silently reduced. The candidate finding takes `MANUAL_REVIEW_REQUIRED`; it cannot become `VALIDATED`, regardless of confidence. PostgreSQL independently requires every validated finding to have at least one citation and rejects a citation outside the check snapshot.

## Source integrity and result ownership

Finding sources have an exact reference matrix:

| Source | Rule execution | AI run |
|---|---:|---:|
| `RULE_ENGINE` | required | prohibited |
| `AI` | prohibited | required |
| `MANUAL` | prohibited | prohibited |

The AI run must be completed and match the finding's organization/check through a composite FK. AI output has no operation for updating `compliance_checks.overall_result`; that value remains owned by deterministic aggregation over executions and validated/review findings.

## Auditability and immutability

`ai_runs` records provider/model/prompt version, input hash/snapshot, retrieved context, raw and validated responses, confidence, idempotency, attempts, timestamps, and errors. Terminal runs (`COMPLETED`, `FAILED`, `INVALID_OUTPUT`, `CANCELLED`) cannot be updated or deleted. A completed historical check cannot accept a new run or finding.
