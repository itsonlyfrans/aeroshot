# WP-06 controller — Focused Video Studio UI

## Mission

Deliver the first focused Video Studio: playback, seek/frame step/J-K-L, trim/split/selected-range deletion, timed annotations, canvas/audio essentials, and real cancellable export—without becoming a general NLE.

## Allowed files

- `Aeroshot/MediaStudio/UI/**`
- `Aeroshot/Recording/RecordingPostCapture.swift`
- `AeroshotTests/VideoStudioModelTests.swift`
- `_bmad-output/evolution/test-reports/WP-06-video-studio.md`

Do not edit media core/export internals, project schema/bridge, recording controller/service/session, screenshot editor, themes, history, or project.pbxproj.

## Required implementation

- MainActor Studio document/model coordinating real media project, AVPlayer, media composition, immutable export snapshot, undoable timeline operations, and save/autosave.
- Native SwiftUI/AppKit window with preview, transport/timecode, thumbnail timeline request/render surface, trim handles, range selection, split/delete, timed overlay list/inspector handoff, crop/canvas, mute/gain, and export progress/cancel/result.
- Keyboard J/K/L, arrows/frame step, Space, I/O or explicit range boundary commands, Delete, undo/redo, focus/accessibility labels/actions, reduced motion.
- Enable post-recording Edit only when a valid media project can be created/open; otherwise expose a reason/recovery action.
- Deterministic model/command tests; UI smoke test hooks without fake media actions.

## Truth and gate

No reorder, freeze/speed, advanced audio, or automatic zoom claim. Gate: recorded MP4 opens, can remove a mistake/add timed callout, save/reopen, and export with preview/export snapshot parity; full tests/build pass.
