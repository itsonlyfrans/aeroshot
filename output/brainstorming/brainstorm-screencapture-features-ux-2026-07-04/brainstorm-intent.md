# ScreenCapture — Brainstorm Intent

**Session:** screencapture-features-ux · 2026-07-04 · Creative Partner  
**Goal:** Polish the daily driver first, then build a differentiated competitive backlog.

## Product pillars (from jobs)

Users hire ScreenCapture for four underlying jobs:

1. **Prove** — bug reports, QA evidence, compliance captures with annotations and consistent filenames
2. **Teach** — tutorials, demos, step annotations, click highlights, GIF repros
3. **Polish & share** — beautify presets, social-ready exports, quick clipboard/share workflows
4. **Extract text** — OCR, receipts, quotes, searchable history

## Polish sprint (Must / Should — ship first)

### Settings information architecture

- Make **Overview read-only**: stat cards and explore grid only; remove duplicate Capture toggles
- **Split or relabel Recording pane**: isolate Scrolling capture into its own nav item or clearly labeled section
- Add **Editor pane** in Settings: beautify defaults, open-after-capture toggle, default tool styles
- **Reset to defaults** per pane + global; **export/import JSON profile** for team consistency

### Discoverability & cohesion

- **First-run permission wizard** consolidating Screen Recording, Input Monitoring, Accessibility
- **Selection overlay**: live W×H dimensions and coordinates during drag
- **Menu bar icon states**: permission warning badge, recording-in-progress variant
- Extend **SettingsInlineCallout** to document pin (scroll resize, ⌥ opacity) and thumbnail shortcuts
- **Keyboard-accessible thumbnail actions**; optional always-visible action strip
- Apply **Settings design system** to History header and empty states (guided first-capture CTA)

### History & media gap

- Add **Recordings tab** (MP4/GIF) alongside All / Images / Text
- **Filename templates** with tokens: `{date}`, `{time}`, `{type}`, `{app}`

## Feature backlog (Could — competitive differentiation)

### Capture profiles

Named presets (Bug Report, Social, Docs) bundling: format, beautify, cursor visibility, delay, destination

### Capture control

- Last-region recall; fixed aspect lock (16:9, 1:1); self-timer delay
- Multi-display picker; window shadow toggle; cursor show/hide in stills

### Workflow integrations

- macOS **Shortcuts actions** for each CaptureIntent
- Quick Share targets (Mail, Messages, custom webhook)
- Optional cloud upload link (CleanShot parity)

### Recording depth

- Mic overlay; pause/resume; GIF size estimate before record
- Webcam bubble for face-cam tutorials

### Editor depth

- Ruler/measurement tool; color eyedropper; annotation templates
- PDF bundle export from History multi-select

### Power user

- AppleScript dictionary; per-app hotkey profiles; batch history operations

## Explicit won't-this-time

- Full cloud sync platform
- Self-hosted API / enterprise SSO
- Real-time collaborative annotation

## Recommended implementation sequence

1. Overview read-only + scrolling pane split + permission wizard
2. Recordings history tab + filename templates + selection dimensions
3. Editor Settings pane (beautify persistence, open-after-capture)
4. Capture profiles v1
5. Shortcuts actions + Quick Share menu

## Success metrics

- Time-to-first-successful-capture for new users (permissions + first shot)
- Settings search hit rate / reduced support confusion on scrolling vs recording
- History engagement (return visits, search usage) after Recordings tab
