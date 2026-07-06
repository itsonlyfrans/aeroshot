# WP-00 golden workflow — Instant screenshot

**Contract status:** Phase 0 product specification. This document defines required behavior; it is not implementation evidence.

## Outcome

A user captures an area, window, or display and immediately copies, saves, or drags the image without opening Studio or completing any extra mandatory step.

## Entry

- Global screenshot shortcut, menu-bar Capture command, or an equivalent accessible command.
- The last-used still-capture mode may be restored, but a user can change area/window/display mode from the capture HUD.
- If Screen Recording permission is unavailable, entry leads to an explanatory recovery state rather than a non-responsive HUD.

## Critical path

1. Invoke capture.
2. The selection HUD becomes interactive over the available displays.
3. Choose an area, window, or display. Keyboard users can move between targets and adjust an area without a pointer.
4. Commit the selection.
5. A non-blocking post-capture thumbnail appears with immediate Copy, Save, Drag, and Edit actions.
6. Copy, Save, or Drag completes without opening Studio. Edit is optional and hands the immutable source into the editable-project workflow.

The capture HUD and thumbnail never require an account, network connection, upload, project-name prompt, or Studio launch on this path.

## Success exit

- **Copy:** the image is on the pasteboard and completion is announced.
- **Save:** a local file is written to the configured or explicitly selected destination and its location is available from the thumbnail.
- **Drag:** the receiving app accepts a local file promise or file; the capture remains locally recoverable until the transfer resolves.
- **Edit:** Studio opens from the captured source without mutating the original.

## Cancellation

- Escape cancels selection before commit and returns focus to the previously active app.
- A visible Cancel action is keyboard reachable and has the same result.
- Dismissing the post-capture thumbnail does not delete a completed capture; it follows the configured local-history/retention policy.
- Cancel never places partial pixels on the pasteboard, writes a misleading final export, or opens Studio.

## Failure recovery

| Failure | Required response and recovery |
|---|---|
| Screen Recording permission missing/revoked | Explain why permission is required; offer Open System Settings and Retry; preserve the requested capture mode. |
| Display topology changes while selecting | Rebuild targets safely or cancel with a clear message; never commit the wrong display region. |
| Capture service fails | Keep the user in a retryable state; offer Retry and Cancel; do not show a success thumbnail. |
| Clipboard write fails | Preserve the completed local capture and offer Retry Copy or Save. |
| Destination is unavailable or disk is full | Preserve the completed capture in recoverable local storage when possible; offer Choose Location and Retry; never claim Save succeeded. |
| App terminates after commit | On next launch, expose the completed capture or a clearly labelled recoverable item when durable data exists. |

## Accessibility contract

- All modes, targets, dimensions, actions, errors, and progress expose meaningful VoiceOver names, values, states, and actions.
- The entire workflow is keyboard-only: invoke, select target, adjust bounds, commit, choose a thumbnail action, retry, and cancel.
- Focus starts on the current capture mode, remains visible, follows logical reading order, and returns predictably on exit.
- Selection is communicated by shape/border and text as well as color. Increased Contrast remains legible.
- Reduced Motion removes nonessential animation; no timeout is required to reach thumbnail actions.

## Privacy and local-first contract

- Captured pixels stay on-device unless the user explicitly chooses an external destination or share action.
- No account, telemetry, cloud sync, or upload is required.
- Diagnostics exclude captured pixels, OCR text, window titles, filenames, and paths unless the user deliberately attaches them to a support report.
- Any automatic local history is visible, user-configurable, deletable, and governed by an explicit retention policy.

## Measurable acceptance criteria

These are release criteria to measure; no result is asserted here.

1. In automated/manual runs covering area, window, and display capture, each mode reaches Copy, Save, and Edit without an intervening required dialog or Studio launch: **9/9 route combinations pass**.
2. Warm command-to-interactive-HUD latency is **p95 ≤ 200 ms** under the Phase 0 measurement protocol.
3. Selection-commit-to-visible-thumbnail latency for a single-display still is **p95 ≤ 500 ms** under that protocol.
4. Keyboard-only and VoiceOver task runs complete invoke → selection → commit → Copy and invoke → selection → cancel with **100% required controls reachable and named**.
5. Permission denial, topology change, clipboard failure, unavailable destination, and disk-full fixtures each end in either an intact prior capture or a discoverable recoverable item, with **0 false success indications and 0 silent data-loss outcomes**.
6. Network-blocked execution completes capture, Copy, Save, Drag, and Edit entry with **0 required network requests**.
7. After Escape before commit, tests observe **no new pasteboard image, final export, Studio window, or completed history item**.

## Open decisions

- Default thumbnail lifetime and the interaction between dismissal, History, and retention.
- Whether a failed Copy keeps the thumbnail indefinitely or moves the item to a recovery collection after a bounded interval.
- Exact keyboard geometry commands for area selection; they must be documented before accessibility approval.
