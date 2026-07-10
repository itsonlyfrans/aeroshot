# Privacy

Aeroshot requests Screen Recording for capture, Camera for webcam overlays, and
Microphone for recorded audio. Access is initiated by the corresponding user
action and governed by macOS. Projects and exports remain local unless the user
explicitly chooses an external destination or sharing action.

Analytics and crash reporting are separate, explicit opt-ins and default off.
The current application includes policy enforcement only—there is no telemetry
network sender. If a sender is added later, it may transmit only allowlisted,
aggregate events after consent. It must never include pixels, recordings, audio,
OCR or clipboard text, filenames, paths, URLs, window titles, user/device names,
email addresses, tokens, or stable device identifiers. Revoking consent must stop
future collection; consent must not be inferred from licensing or updates.
