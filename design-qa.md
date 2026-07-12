# Design QA — Aeroshot Slate & Coral

Reference: `Screenshot tool settings design.zip` → `Aeroshot Redesign.dc.html`

## Result

final result: passed

## Visual comparison

- Settings reference and native app: `output/design-qa/settings-comparison.png`
- Onboarding reference and native app: `output/design-qa/onboarding-comparison.png`
- App-only settings capture: `output/design-qa/aeroshot-settings-slate-coral.jpg`
- App-only onboarding capture: `output/design-qa/aeroshot-onboarding-slate-coral.jpg`

The native implementation matches the supplied graphite/slate surfaces, coral accent, compact navigation rail, branded `A` mark, permission warning treatment, overview card hierarchy, and four-step setup structure. SF Symbols and macOS system typography are retained as the native equivalents of the HTML board's icon and font treatments.

## Coverage

- Shared Slate & Coral tokens and AppKit drawing paths
- Overview, Capture, Output, Shortcuts, Recording, Scrolling, Editor, and System settings panes
- Four-step permission onboarding
- After-capture thumbnail and hover action rail
- Selection overlay, annotation editor, and video/GIF editor accent states
- Keyboard focus, accessibility labels, reduced-motion transitions, and live permission status

## Verification

- `xcodebuild ... build` — passed
- `xcodebuild ... test -only-testing:AeroshotTests` — passed
- `design-lint.mjs` on the touched UI files — no errors; remaining notices are advisory preview/compact-target heuristics
- Computer Use app-only window inspection — passed for onboarding and settings
- Side-by-side reference comparison — passed after correcting the brand mark, onboarding alignment, and exact setup copy

The full scheme's UI-test runner crashed before bootstrapping in the local host environment; the unit target passed and native-window behavior was verified directly through the app accessibility surface.
