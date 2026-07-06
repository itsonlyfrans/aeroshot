# WP-00 golden workflow — Recorded demo edited to MP4 or GIF

**Contract status:** Phase 0 product specification. Existing MP4/GIF capture is output-only; preflight, pause/resume, recovery, editable projects, timeline correction, and reliable editable MP4/GIF export described here are planned behavior.

## Outcome

A product maker records a local screen demo, safely pauses or recovers from interruption, removes a mistake, adds a timed callout, and exports a shareable MP4 or GIF without using another editor.

## Entry

- Global recording shortcut, menu-bar Record command, or an equivalent accessible command.
- Recording preflight identifies source (area/window/display), resolution, frame rate, cursor, system audio, microphone/device, webcam, and countdown.
- GIF is an output choice from the same editable recording project; choosing it does not require a second capture.

## Critical path

1. Open preflight and select a source. Review visible permission, audio-meter, destination-space, and estimated-resource status.
2. Start after the selected countdown. A persistent, non-captured recording indicator exposes elapsed time, Pause/Resume, Stop, and Cancel.
3. Pause, then resume. Timeline timestamps compensate for the pause so media remains synchronized.
4. Stop. Aeroshot finalizes durable media and a recoverable session manifest before presenting success.
5. A post-recording thumbnail offers Edit, Copy/Drag, Save, and Reveal. Choose Edit.
6. Studio opens an editable project without destructive transcoding of the original recording.
7. Play/seek, set an in/out trim or delete one selected mistake range, and add one timed callout.
8. Preview the same project snapshot that export will consume.
9. Choose MP4 or GIF in Export:
   - **MP4:** choose a documented H.264/HEVC preset, dimensions, and frame rate.
   - **GIF:** choose dimensions, effective frame rate/timing, loop behavior, and a quality/size preset with an estimate.
10. Start export, observe progress, and finish to a user-selected local destination.

## Success exit

- The local MP4 or GIF opens in an independent viewer and reflects the approved trim/range deletion and timed callout.
- Audio/video synchronization and duration are within approved tolerances for MP4.
- GIF timing and loop metadata match the displayed effective settings.
- The editable local project and immutable original remain available after export.

## Cancellation

- Cancel before recording returns to the prior app with no session artifact presented as a recording.
- Cancel during recording requires an explicit Keep Recoverable Recording or Discard confirmation; destructive discard identifies what will be removed.
- Cancel export stops background work, returns to the intact project, and removes/quarantines incomplete output.
- Escape never silently discards a durable recording, project edit, or completed export.

## Failure recovery

| Failure | Required response and recovery |
|---|---|
| Screen Recording, microphone, or camera permission denied/revoked | Identify the affected input, offer Open System Settings/Retry, and allow a reduced configuration when valid; never imply an unavailable source is recording. |
| Insufficient disk space before start | Block start, show required/available space and destination, and offer Choose Location/Retry. |
| Low space during recording/export | Stop or cancel safely, preserve finalized media and the recoverable manifest/project where possible, and expose cleanup/retry actions. |
| Capture stream/app interruption | Finalize usable partial media when possible; on relaunch expose a recoverable session with actual duration and missing-track warnings. |
| Audio device disconnects | Mark the event, continue valid tracks when possible, and make the gap explicit in Studio/export validation. |
| Export encoder fails or hardware fallback occurs | Preserve the project; disclose fallback before or during export, provide Retry/settings alternatives, and never leave an apparently complete corrupt file. |
| GIF target cannot honor requested timing | Display effective timing and encode/test that value; do not silently claim the requested rate. |

## Accessibility contract

- Preflight fields, meters, recording state, elapsed time, transport, timeline selection, timed annotations, export settings, progress, errors, and recovery actions expose meaningful VoiceOver information.
- The complete workflow is keyboard operable, including Pause/Resume and Stop via configurable shortcuts, timeline seek/range selection, callout timing, export, cancel, and recovery.
- Recording state is indicated by text/icon/state, not color alone. Critical actions remain legible in Increased Contrast.
- Reduced Motion suppresses decorative HUD/Studio transitions without hiding state changes.
- Countdown, elapsed time, audio levels, and export progress are announced without excessive repetitive speech.

## Privacy and local-first contract

- Capture, event tracks, editing, preview, and export operate without an account or mandatory network connection.
- Microphone, camera, system audio, cursor/click, and any keystroke event capture are individually visible. Keystroke capture is opt-in, visibly indicated, and excludes secure-input contexts.
- Event tracks are inspectable and deletable before export. Captured content, transcripts, event details, filenames, and paths are excluded from diagnostics by default.
- No media or event track is uploaded unless the user explicitly chooses an external share destination after reviewing what will leave the device.

## Measurable acceptance criteria

These are release criteria to measure; no result is asserted here.

1. Deterministic 10-, 30-, and 60-minute MP4 fixtures with pause/resume maintain **absolute A/V drift ≤ 50 ms**; reported duration excludes paused intervals within the approved timestamp tolerance.
2. Supported-hardware recording fixtures show **< 0.5% unintended dropped complete frames** under the Phase 0 protocol, with source rate and dropped-frame definition recorded.
3. Permission denial, cancel, interruption, low-space, microphone disconnect, and relaunch fixtures each produce either a valid prior project or a discoverable recoverable session; **0 fixtures end in silent data loss or false success**.
4. A completed recording opens as an editable project with **no destructive transcode of the immutable original**.
5. The task record → pause/resume → stop → trim/delete one range → add timed callout → export completes for **both MP4 and GIF**, and each result opens in an independent viewer.
6. MP4 preview/export visual parity, duration, callout time range, dimensions, frame rate, and color result meet their approved tolerances in **100% of the golden corpus**.
7. GIF loop count/forever choice, effective frame timing, dimensions, and callout timing match inspected metadata/rendered frames in **100% of the golden corpus**.
8. A 60-second 1440p GIF-editing fixture does **not show RSS growth linear with recording duration** and remains below the separately measured, hardware-specific Phase 0 ceiling.
9. Export progress appears within **500 ms**, remains cancellable throughout, and a cancelled export leaves **no file presented as complete**.
10. Keyboard-only and VoiceOver runs complete preflight → record → pause/resume → stop → trim → callout → MP4/GIF export with **100% required controls reachable, named, and stateful**.
11. A network-blocked run completes recording, editing, recovery, and local export with **0 required network requests**.

## Open decisions

- Exact MP4 preview/export visual and color tolerances.
- Hardware-specific memory ceiling and fixture duration/resolution matrix for GIF editing.
- Initial GIF quality presets, supported effective timing floor, and size-estimation error tolerance.
- Whether selected-range deletion is gap-closing in the first slice; arbitrary clip reordering and full ripple editing remain out of scope.
- Default retention and user wording for Cancel → Keep Recoverable Recording versus Discard.
