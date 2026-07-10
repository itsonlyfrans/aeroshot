# WP-01 project kernel — gate evidence

**Date:** 2026-07-10  
**Status:** WP-01 implementation gate passed; `EditorDocument` integration is intentionally deferred to its separately scoped work package.

## Implemented production surface

- Versioned `AeroProjectManifest` with compatibility metadata and stable identifiers for assets, overlays, timeline items, event tracks, and export presets.
- Exact, normalized rational media timestamps and time ranges that decode through validating initializers without floating-point conversion.
- Immutable-original asset records with SHA-256 checksums, byte counts, media metadata, and explicit primary-source ownership.
- Canvas, typed overlay, timeline/event/export placeholder schemas, generated-cache policy, and recovery-generation metadata.
- Explicit schema migration entry point supporting legacy version 0, current-version round trips, corrupt-data rejection, incompatible-reader rejection, and future-version rejection.
- Package store with validated relative paths, `..`/absolute/backslash rejection, symlink-escape rejection, immutable-original enforcement, checksum and byte-count validation, atomic manifest replacement, durable file synchronization, and recoverable prior generations.
- Debounced autosave actor that coalesces snapshots, supports lifecycle flush/cancel, preserves failed snapshots for retry, and exposes a deterministic immediate-flush seam for tests.

## Deterministic WP-01 coverage

`AeroshotTests/AeroProjectTests.swift` contains 10 tests covering:

1. current-schema round trip and exact rational-time normalization;
2. version 0 migration defaults;
3. unknown future schema rejection;
4. corrupt manifest rejection;
5. lexical and symlink path traversal rejection;
6. checksum mismatch detection;
7. immutable-original overwrite/rebinding rejection;
8. injected pre-replacement failure preserving the current manifest;
9. recovery from a corrupt current manifest to the latest valid prior generation; and
10. autosave coalescing and immediate deterministic flush without wall-clock waiting.

## Validation results

Command:

```sh
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/aeroshot-wp01-dd \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:AeroshotTests/AeroProjectTests
```

Result: **passed, 10/10 WP-01 tests**.

Full unit target command:

```sh
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/aeroshot-wp01-dd \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:AeroshotTests
```

Result: **passed, 90/90 tests; 0 failures**.

## Gate assessment

- Round trip, migration, corruption, atomic-failure, and recovery evidence: **PASS**.
- Original assets cannot be silently overwritten or rebound: **PASS**.
- Generated data is explicitly purgeable and separate from originals: **PASS at schema boundary**; cache eviction execution belongs to a later generated-media work package.
- Current capture behavior changed: **NO**.
- `EditorDocument` routing through `AeroProject`: **DEFERRED by WP-01 controller file boundaries**; the project API is ready for the integration package.

WP-01's bounded gate is complete.
