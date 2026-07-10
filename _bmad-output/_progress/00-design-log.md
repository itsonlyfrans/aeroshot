# Aeroshot design log

## Current

- WP-00 Product contract and reference evidence are approved. Phase 1 is in progress.
- Source of truth: `docs/plans/2026-07-10-aeroshot-product-evolution-combined.md`.
- Execution controller: `_bmad-output/evolution/work-packages/WP-00-controller.md`.
- Phase 1 is authorized; deferred oldest-hardware and accessibility evidence remains tracked for later gates.

## Decisions

- Preserve the fast capture path and expose Studio only on deliberate edit actions.
- Treat screenshot, video, and GIF work as one local-first project family.
- Keep original assets immutable and edits reversible.
- Do not claim the existing Luna review as identity-verified.
- Use paid signed distribution with source available as the reversible architecture recommendation; no license or price is approved until Owl decides.
- Treat the M4 Max test/build run as reference-machine toolchain evidence only, not product-performance evidence.
- Owl approved the recommended defaults, removed verified Luna identity as a blocker, and deferred oldest-hardware benchmarks on 2026-07-10.

## Unresolved

- Final license text, pricing, and update/entitlement policy.
- Named oldest-supported hardware and measured quality-budget baselines before release candidacy. Current M4 Max evidence does not represent the oldest supported hardware.

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
- 2026-07-10: Owl approved the recommended Phase 0 defaults, removed the Luna identity blocker, deferred oldest-hardware benchmarks to the release harness, and authorized Phase 1 plus subsequent phases.
