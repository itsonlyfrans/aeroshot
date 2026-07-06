# Aeroshot design log

## Current

- WP-00 Product contract drafts and reference evidence are complete; the phase remains gated.
- Source of truth: `docs/plans/2026-07-10-aeroshot-product-evolution-combined.md`.
- Execution controller: `_bmad-output/evolution/work-packages/WP-00-controller.md`.
- Phase 1 is gated on approved workflows, distribution scope, visual references, measured budgets, and verified Luna review.

## Decisions

- Preserve the fast capture path and expose Studio only on deliberate edit actions.
- Treat screenshot, video, and GIF work as one local-first project family.
- Keep original assets immutable and edits reversible.
- Do not claim the existing Luna review as identity-verified.
- Use paid signed distribution with source available as the reversible architecture recommendation; no license or price is approved until Owl decides.
- Treat the M4 Max test/build run as reference-machine toolchain evidence only, not product-performance evidence.

## Unresolved

- Final initial distribution boundary: fully open source, open core, or paid signed distribution with source available.
- Verified Luna-model review.
- Named oldest-supported hardware and approved, measured quality-budget baselines. Current M4 Max evidence does not represent the oldest supported hardware.
- Approval of high-fidelity visual references and golden workflows.

## Backlog

- WP-01 Project kernel
- WP-02 Unified design system
- WP-03 Annotation engine
- WP-04 Recording session
- WP-05 Media core
- WP-06 Video Studio
- WP-07 GIF Studio
- WP-08 Library and distribution
- WP-09 Release harness

## History

- 2026-07-10: Began WP-00 and added the scoped execution controller. No application code changed.
- 2026-07-10: Drafted three golden workflows, the product contract, distribution recommendation, visual direction, light/dark reference board, performance protocol, and gate records. Unit tests and a warm incremental build passed on the reference M4 Max; application performance remains unmeasured. Phase 1 remains blocked by the verified-Luna and approval/evidence gates.
