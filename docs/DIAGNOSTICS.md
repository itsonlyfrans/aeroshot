# Aeroshot diagnostics

Aeroshot diagnostics are off by default and stay on the Mac. Enabling consent only permits a bounded, in-memory list of content-free operational outcomes. Aeroshot has no diagnostics network sender and makes no claim that a crash-reporting service is installed.

## Data boundary

Allowed diagnostic values are a fixed subsystem, a fixed outcome, timestamps, a small allowlist of integer counters, and a small allowlist of Boolean recovery flags. The model cannot contain arbitrary strings or binary data. Unknown fields are dropped.

Diagnostics and support bundles exclude screen pixels, thumbnails, OCR or clipboard text, keyboard/mouse event data, window titles, filenames, filesystem paths, URLs, user-entered labels, tokens, credentials, and secrets. Error descriptions and stack traces are not collected because they can contain paths or content.

## Consent and export

- Consent has no implicit or migration default: an absent preference means disabled.
- Disabling consent prevents new events. The user can clear the current in-memory events.
- Export is an explicit user action to a caller-selected local file.
- The support bundle is atomically written JSON with the same typed, sanitized event schema.
- No upload, background transmission, endpoint, device identifier, or cross-launch event database exists.

Before sharing a bundle, users should review the local JSON. Support should request only this bundle and never request a project package or capture unless the user knowingly chooses to provide one separately.
