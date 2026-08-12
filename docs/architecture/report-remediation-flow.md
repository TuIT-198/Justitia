# Report, Remediation, and Re-check Flow

## Historical model

```text
completed check #1
  -> report v1 draft
  -> finding and citation snapshots
  -> submission round(s)
  -> approved report v1 (locked)
  -> remediation tasks
  -> exact verified evidence
  -> accepted evidence + task review
  -> approved remediation
  -> queued check #2 (parent_check_id = check #1)
  -> separately selected evidence/law + compliance processing
  -> completed check #2
  -> report v2 (parent_report_id = report v1)
```

Old rows are never repurposed as newer versions. A check has zero or one report; each re-check is a new check row, and its report is created only after that check completes.

## Atomic report snapshot

`generate_compliance_report` accepts only a completed same-tenant check and derives the batch, overall result, parent report, and version. In one transaction it creates:

1. The draft report header.
2. One `report_findings` row for every check finding.
3. One `report_finding_citations` row for every source finding citation.

The report stores finding display content and citation/legal provenance rather than depending on future joins for rendering. Validated findings without legal citations fail generation. Submission repeats a completeness check, so removing a draft snapshot cannot produce an incomplete approved report.

The citation snapshot follows the exact source row through section, legal version, document, and legal source. It also records the legal-version content hash. An original-file checksum is stored only when the version has one unambiguous original checksum; ambiguity is represented as NULL rather than guessed.

## Submission and approval

The lifecycle is:

```text
DRAFT -> PENDING_APPROVAL -> APPROVED
                         \-> REJECTED -> DRAFT -> PENDING_APPROVAL
```

Every submission increments `submission_round`. Decisions are appended to `report_approvals`; they are never overwritten. `REPORT_APPROVE` is assigned to OWNER and MANAGER. Once approved, the report header and all snapshot/history children are immutable. Corrections require reassessment and a later report, not mutation of approved history.

## Remediation evidence

A remediation task points to an approved report and one finding included in that report. Multiple active organization members may be assigned.

Evidence never points only to a document identity. It identifies the exact same-tenant document revision and matching verification, and both must be `VERIFIED`. Submission history is retained; reviewed evidence cannot be rewritten or deleted. Evidence must be accepted before the task enters review, and the task requires an append-only approved review before reaching `APPROVED`.

All MVP tasks are considered required. A task in any status other than `APPROVED` blocks re-check.

## Re-check gate and snapshot selection

An OWNER/MANAGER with `COMPLIANCE_RECHECK` may create a re-check only when the source report is approved and its source check is completed. If tasks exist, all must be approved and have accepted verified evidence. An approved report with no tasks can be explicitly re-checked by an authorized user.

The operation creates only a new `QUEUED` check with:

```text
same organization and batch
parent_check_id = source check
next batch check_number
new non-empty idempotency key
```

It intentionally does not copy old document/legal snapshots and does not run deterministic or AI analysis. A later orchestration layer must deliberately choose current verified evidence and applicable legal versions. This prevents stale evidence or changed law from being copied blindly.
