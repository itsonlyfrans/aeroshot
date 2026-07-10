# WP-09 — UI and accessibility validation

## Automated scope

Run with the signed runner:

```sh
scripts/run-ui-tests.sh
AEROSHOT_UI_FILTER=AeroshotUITests/testPermissionRecoveryAndAccessibilitySurface scripts/run-ui-tests.sh
AEROSHOT_UI_RESULT_BUNDLE=/tmp/AeroshotUI.xcresult scripts/run-ui-tests.sh
```

The runner verifies Developer Mode, refuses `CODE_SIGNING_ALLOWED=NO` and
`CODE_SIGNING_REQUIRED=NO`, and leaves Xcode signing enabled so Gatekeeper does
not report the generated UI test runner as damaged.

Automated coverage includes:

- launch and permission recovery through the supported privacy-review route;
- permission recovery labels/roles/states and the keyboard Settings command;
- reduced-motion/increased-contrast launch environment smoke coverage;
- deterministic `.aeroshot` fixture open, editor tool labels/selection/disabled
  state, project save, and direct screenshot export controls;
- instant screenshot and recording entry when the host TCC state permits them.
- retained screenshot attachments for light, dark, Increased Contrast, and
  Reduce Motion Settings fixtures.

## Permission matrix and manual checklist

TCC grants cannot be created safely or reliably by XCTest. Run these rows on a
signed installed build and again after revoking each grant in System Settings.

| Permission | Without grant | With grant | Manual accessibility evidence |
|---|---|---|---|
| Screen Recording | Capture/record explains that permission is required and offers recovery; automated workflow skips with this exact reason. | Full-screen capture reaches thumbnail/editor without mandatory Studio; record-screen reaches preflight, HUD, stop, and Video/GIF Studio. | VoiceOver announces requirement, recovery action, recording state, elapsed time, pause/resume, and stop. |
| Accessibility | Global shortcuts/auto-scroll remain unavailable with a visible reason; ordinary launch is not blocked by a modal alert. | Global shortcuts and scrolling auto-scroll work. | Keyboard-only navigation reaches the permission recovery control; VoiceOver announces granted/not granted. |
| Microphone | Recording with microphone enabled explains the missing grant and cannot start silently. | Audio-meter/input selection and recorded audio work. | VoiceOver announces microphone state and why Start Recording is disabled. |
| Camera | Webcam-enabled recording explains the missing grant and cannot start silently. | Preview, placement, and recorded webcam overlay work. | VoiceOver announces camera state, preview, placement actions, and disabled reason. |

Additional manual checks:

1. Enable VoiceOver and traverse onboarding, Settings permissions, capture
   recovery, editor toolbar, recording preflight/HUD, Video Studio, and GIF
   Studio. Confirm labels, values, selected/disabled state, and custom actions.
2. Repeat keyboard-only with Full Keyboard Access enabled: no focus trap, all
   primary/recovery/export controls reachable, Escape cancels transient UI.
3. Repeat with Reduce Motion, Increase Contrast, Reduce Transparency, and
   Differentiate Without Color enabled. Confirm no information relies only on
   animation, translucency, or color.
4. Verify the Screen Recording row once with screenshot output configured for
   direct save/clipboard and once for editor-after-capture. Neither may require
   Video/GIF Studio.
5. The current desktop test session reported `Failed to synthesize event: Timed
   out while synthesizing event` for generated Command-key events (with display
   geometry `(inf, inf, 0, 0)`). Keyboard traversal therefore remains a manual
   gate on an interactive desktop; automated tests assert the keyboard command
   remains present in the accessibility menu tree without synthesizing input.

## Gate truth

Automated tests may skip only the screenshot/recording methods and only when the
real signed test host lacks Screen Recording access. Microphone, Camera,
Accessibility global-shortcut behavior, VoiceOver speech quality, and the full
recording lifecycle remain explicit manual gates because XCTest cannot grant or
hear those OS-level states.

## Executed validation

- Signed focused command: `AEROSHOT_UI_FILTER=AeroshotUITests/testPermissionRecoveryAndAccessibilitySurface AEROSHOT_UI_RESULT_BUNDLE=/tmp/AeroshotWP09-focus.xcresult scripts/run-ui-tests.sh`
- Result: passed, 1 test, 0 failures, 4.367 seconds.
- Signing evidence: app, UI test bundle, and `AeroshotUITests-Runner.app` were
  signed with the configured Apple Development identity; no damaged-runner
  warning occurred.
- Full signed UI suite passed 6/6 in the final uncontended window. Screenshot
  and recording methods retain exact Screen Recording TCC skips; keyboard event
  synthesis and VoiceOver remain the manual gates described above.
- Four visual-fixture methods were subsequently added. The runner script holds
  a `caffeinate` assertion so a visible desktop remains available throughout the
  run. The final signed suite passed 10/10 in 54.066 seconds and retained valid
  window screenshots for light, dark, Increased Contrast, and Reduce Motion;
  the runner produced no Gatekeeper damage warning.
