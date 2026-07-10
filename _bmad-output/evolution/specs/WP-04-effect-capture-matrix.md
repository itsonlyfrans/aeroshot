# WP-04 effect-capture matrix

**Status:** Implemented domain policy; no live capture/UI integration is claimed.

The policy is represented by `RecordingEffectCapturePolicy.matrix`. Every row is excluded from diagnostics. “Metadata” means inspectable and deletable after capture; “baked” is an explicit capability fallback and is not later editable.

| Effect | Disabled when | Preferred capture | Fallback | Privacy constraints |
|---|---|---|---|---|
| Cursor | Cursor mode is hidden | Editable metadata | Baked into media | Diagnostics-excluded |
| Click | Click capture and click effects are off | Editable metadata | Baked into media | Diagnostics-excluded |
| Keystroke | Not opted in, indicator not visible, or secure input active | Editable metadata only | Disabled; never baked | Opt-in, visibly active, secure-input excluded, inspectable, deletable, diagnostics-excluded |
| Webcam | No webcam selected | Editable separate-stream metadata | Baked into media | Metadata is inspectable/deletable; all modes diagnostics-excluded |

## Deterministic decision rules

1. The matrix returns exactly one decision in `RecordingEffectKind.allCases` order.
2. Metadata availability controls cursor, click, and webcam fallback independently.
3. Keystrokes have no baked fallback. Capture requires all three conditions: explicit opt-in, a visible-active indicator, and secure input not active.
4. Only editable metadata is reported as inspectable/deletable. A baked fallback is disclosed by `storage == .bakedIntoMedia`.
5. Captured pixels and event details remain excluded from diagnostics regardless of storage mode.

## Integration boundary

The kernel returns policy decisions. A future capture adapter must implement those decisions, present the visible keystroke indicator, observe secure-input state, and disclose baked fallbacks. WP-04 does not assert that current ScreenCaptureKit services or UI use this policy.
