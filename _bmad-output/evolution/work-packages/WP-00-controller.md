# WP-00 execution controller — Aeroshot product contract

Working directory: `/Users/owl/Developer/screencapture`

## Mission and current phase

Implement only Phase 0 / WP-00 from `docs/plans/2026-07-10-aeroshot-product-evolution-combined.md`. Phase 1 and later code are forbidden until the Phase 0 gate is approved. The current working copy contains extensive user changes; preserve them and do not reformat, reset, delete, stage, or commit unrelated files.

## Sources of truth

Read these before acting:

1. `docs/plans/2026-07-10-aeroshot-product-evolution-combined.md`
2. `docs/plans/2026-07-10-aeroshot-product-evolution-plan.md`
3. `docs/plans/2026-07-10-luna-review-brief.md`
4. `docs/plans/2026-07-10-luna-review-record.md`
5. `_bmad/wds/config.yaml`
6. Repository and user `AGENTS.md` instructions supplied by the host

Search before introducing concepts. The combined plan is authoritative if duplicated artifacts differ.

## Scope and artifacts

Allowed output paths:

- `_bmad-output/evolution/scenarios/WP-00-*.md`
- `_bmad-output/evolution/specs/WP-00-*.md`
- `_bmad-output/evolution/test-reports/WP-00-*.md`
- `_bmad-output/evolution/references/WP-00-*`
- `_bmad-output/evolution/work-packages/WP-00-*.md`
- `_bmad-output/_progress/00-design-log.md`
- `.ass/skill-traces/2026-07-10.jsonl`

Do not modify app code, project files, existing plans, website files, or the user's unrelated working-copy changes in WP-00.

Required artifacts:

1. Three golden workflows: instant screenshot, annotated documentation image, and recorded demo edited to MP4/GIF. Each names entry, critical path, success exit, cancellation, failure recovery, accessibility, privacy, and measurable acceptance criteria.
2. A short PRD and interaction specification for the first sellable vertical slice.
3. A distribution-boundary decision record that separates a reversible recommendation from the user's final licensing decision.
4. A performance-budget and measurement protocol, plus an evidence report containing only measurements actually run.
5. Light/dark visual references for capture HUD, Studio, timeline, inspector, export sheet, and history, with accessibility states and explicit non-copying constraints.
6. A Luna gate record. Never claim verified Luna identity unless the host/model can attest it.
7. An updated design log and gate checklist.

## Delegation and non-overlap

- Workflow/PRD agent: may write only `scenarios/WP-00-*` and `specs/WP-00-product-contract.md`.
- Visual-reference agent: may write only `references/WP-00-*` and `specs/WP-00-visual-direction.md`.
- Evidence agent: may write only `test-reports/WP-00-*` and `specs/WP-00-performance-budgets.md`.
- Controller: owns the distribution decision record, Luna gate record, design log, integration review, and all version-control actions.

Agents must not invent parallel project schemas, design systems, or implementation architecture. Cross-file recommendations go in their assigned report; only the controller reconciles them.

## Hard-truth rules

- Do not present a mock, design reference, placeholder, future feature, or unmeasured budget as implemented evidence.
- Do not mark the Luna gate verified from the existing unverified review.
- Do not invent customer evidence, willingness-to-pay, performance results, accessibility results, or external validation.
- Do not enable or alter product behavior during WP-00.
- Do not delete tests, widen permissions, log secrets or captured content, or add destructive behavior.
- Record unresolved decisions explicitly; a partially satisfied gate stays open.

## Validation

Run and record, without changing signing or deployment settings:

```sh
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests test CODE_SIGNING_ALLOWED=NO
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

For performance evidence, record machine model, CPU, memory, macOS version, display scale/color assumptions, warm/cold state, fixture, sample count, percentile method, and background-load caveats. If a metric cannot be measured in this environment, provide an executable protocol and label the result `NOT MEASURED`.

## Gate

WP-00 is complete only when the three workflows, scope boundary, visual references, budgets, and a verified Luna review are approved. Otherwise report `BLOCKED` or `PARTIAL` with exact missing evidence. Phase 1 must not begin while the gate is open.

## Final report contract

Report: phase implemented; files changed; what is real; what remains planned; issues found/fixed/deferred; security/privacy and design status; commands passed/failed/blocked; manual QA; gate status; and whether it is safe to proceed.
