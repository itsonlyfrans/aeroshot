# Luna review brief: Aeroshot product evolution

## Required reviewer identity

Run this brief with the actual Luna model. At the top of the response, record:

- model name shown by the host;
- model/version identifier, if exposed;
- host/application;
- review date.

If the host cannot attest that the reviewer is Luna, stop and label the review **UNVERIFIED MODEL IDENTITY**.

## Objective

Critique and improve Aeroshot's roadmap for becoming a polished, commercially credible macOS screenshot, screen-recording, GIF-editing, and advanced-annotation product.

Primary artifact:

- `docs/plans/2026-07-10-aeroshot-product-evolution-plan.md`

## Current product facts

Treat these as repository-audited facts:

- Aeroshot is a Swift 6 macOS app with a macOS 14.6 deployment target.
- It already captures areas, windows, displays, scrolling content, MP4, and GIF.
- Recording already supports system audio, microphone audio, click highlighting, and a webcam overlay.
- It already has OCR, ShareSafe redaction, history, pinning, beautification, crop, undo/redo, and 11 annotation kinds.
- A selected annotation can be moved or deleted.
- It lacks an editable project format, video/GIF timeline, pause/resume, full annotation transforms, arrowhead controls, and media-specific automated tests.
- GIF capture currently retains full `CGImage` frames in memory, writes one fixed frame delay, and forces infinite looping.
- The global design token set is much smaller than the Settings-specific design system.

## Competitive references

Review current official material from:

- CleanShot X: <https://cleanshot.com/>
- CleanShot X changelog: <https://cleanshot.com/changelog>
- Longshot: <https://longshot.chitaner.com/blog/allfeatures/>
- Shottr: <https://shottr.cc/>
- Screen Studio: <https://screenstudio.net/en/>

Use other competitors only when they add a distinct workflow lesson. Prefer first-party product pages, documentation, changelogs, or help centers. Separate verified facts from inference.

## Review questions

1. Is “fast capture utility with an optional Studio” the right product shape? Identify a stronger alternative if not.
2. Which three workflows should define the first commercially credible release?
3. Which roadmap features are table stakes, which are differentiators, and which are distracting scope?
4. Does the proposed `AeroProject` model correctly unify still images, video, GIFs, annotations, and export presets?
5. What should be cut from the first two release milestones?
6. Which interaction details make premium Mac apps feel custom and Apple-quality without copying Apple or competitor trade dress?
7. What editor layout and progressive-disclosure model best supports novices and precision users?
8. Are the provisional latency, frame-time, sync, memory, recovery, reliability, and accessibility budgets credible?
9. What product, technical, privacy, licensing, or commercialization risks are missing?
10. What is the strongest defensible positioning for an open-source and/or paid Aeroshot?

## Required output

Return one structured review containing:

1. **Verdict** — proceed, revise, or reject the direction, with a short rationale.
2. **Top five corrections** — ordered by expected impact.
3. **Workflow recommendation** — three golden workflows with entry, critical path, exit, and recovery.
4. **Feature triage** — Keep now / Later / Remove.
5. **UX direction** — concrete layout, component, motion, inspector, and timeline principles.
6. **Architecture critique** — risks and changes to the project/render/media boundaries.
7. **Commercial critique** — audience, positioning, open-source/paid boundary, and evidence still needed.
8. **Scorecard** — 1–5 scores for usefulness, differentiation, feasibility, coherence, native Mac quality, accessibility, privacy, and release readiness.
9. **Plan patches** — exact replacement or insertion text for the primary plan.
10. **Evidence** — direct source links beside supported claims and an uncertainty list.

## Review constraints

- Do not assume missing functionality is absent until it is checked against the current facts above.
- Do not propose a general-purpose nonlinear video editor.
- Do not recommend a renderer rewrite, Metal adoption, cloud account, or AI feature without a measured requirement.
- Preserve local-first operation and instant capture paths.
- Treat model identity, competitor facts, and technical API claims as verifiable evidence, not implication.
