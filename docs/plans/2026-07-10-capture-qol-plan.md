# Plan: Capture overlay and editor quality-of-life

**Goal:** Make the post-capture thumbnail compact and dismissible, let users choose its visible actions, and simplify the annotation-to-export workflow.
**Date:** 2026-07-10
**Spec / context link:** User feedback in current task

## Scope

| In | Out |
|---|---|
| Swipe/drag dismissal and a compact thumbnail action strip | New annotation tools or a new capture mode |
| Persistent user selection of visible thumbnail actions | Changing screenshot/redaction behavior |
| Clearer editor export hierarchy and copy | Full editor canvas redesign |

---

## Phase 1 — Thumbnail interaction model

**Goal:** The thumbnail has one clear default action row, can be dismissed by swipe or close, and retains keyboard/accessibility alternatives.

**Tasks:**
- [x] Add a thumbnail action model and persisted visible-action selection.
- [x] Implement drag-to-dismiss with a visible directional response and an accessible close button.
- [x] Consolidate the thumbnail controls into a compact primary row plus an overflow menu.

**Gate:** A thumbnail can be closed via drag, close button, or timeout; visible action selection survives relaunch.

---

## Phase 2 — Settings and editor handoff

**Goal:** Users can choose which primary actions appear and understand that Edit leads to deliberate export.

**Tasks:**
- [x] Add action visibility controls to Capture settings.
- [x] Tighten editor export controls so Save is visually primary and secondary actions do not crowd it.
- [x] Update user-facing labels and accessibility hints.

**Gate:** Settings map directly to thumbnail behavior; the editor’s default export path is obvious.

---

## Phase 3 — Verification

**Goal:** Preserve capture output behavior while confirming interaction state coverage.

**Tasks:**
- [x] Add focused model/persistence tests.
- [x] Build and run the Aeroshot unit suite.
- [ ] Perform a manual visual sweep of thumbnail hover, drag dismiss, overflow, and editor export. (UI test runner is currently killed before bootstrapping.)

**Gate:** Tests pass and manual visual items are either verified or explicitly called out.

---

## Acceptance criteria

- [x] Thumbnail has no more than three visible primary actions by default.
- [x] Users can change the visible action set in Settings.
- [x] Dragging the thumbnail away dismisses it without triggering an action.
- [x] Every hidden action remains reachable through an overflow menu.
- [x] Editor presents a single primary save/export action.

## Validation commands

```text
xcodebuild -quiet -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```
