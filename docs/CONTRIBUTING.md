# Contributing

Build and run the unit suite described in [BUILDING.md](BUILDING.md). Keep capture,
editing, export, and `.aeroshot` project portability independent of licensing,
telemetry, update services, and network availability. New telemetry fields must
be aggregate, content-free, allowlisted, tested, and disabled by default.

Use the repository's `jj` workflow. Do not commit signing certificates,
notarization credentials, provisioning profiles, exported archives, captured
user media, or derived data. Changes affecting permissions or collected data
must update `PRIVACY.md`, `SECURITY.md`, and their tests in the same change.
