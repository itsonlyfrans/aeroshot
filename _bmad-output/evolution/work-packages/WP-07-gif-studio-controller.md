# WP-07 controller — GIF Studio UI

## Mission

Deliver a focused GIF Studio using the bounded GIF core and project bridge: range editing, timing, looping, quality/size controls, preview, and real atomic export.

## Allowed files

- `Aeroshot/GIFStudio/UI/**`
- `AeroshotTests/GIFStudioModelTests.swift`
- `_bmad-output/evolution/test-reports/WP-07-gif-studio.md`

Do not edit GIF core/writer/service, project schema/bridge, recording, Video Studio, screenshot editor, themes, history, or project.pbxproj.

## Required implementation

- MainActor document/model coordinating GIF project, exact edit commands, undo/redo, autosave, bounded preview decoding, estimate, export progress/cancel/result.
- UI for frame/range selection, trim/split/delete/duplicate, range duration, loop once/count/forever, ping-pong, dimensions, palette, dither, transparency, and quality/size comparison.
- Keyboard and VoiceOver-accessible timeline/range/value controls; reduced motion; clear effective timing when target playback is constrained.
- Deterministic command/model tests and real small export integration.

## Truth and gate

No changed-region optimization claim. Gate: 60-second project opens without duration-scaled decoded memory, edits save/reopen, export valid/cancellable, full tests/build pass.
