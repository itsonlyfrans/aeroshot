# WP-08 — Export recipes and destinations

Date: 2026-07-10

## Delivered

- Codable, deterministic built-in recipes for documentation, square/landscape social output, retina assets, and downscaled assets.
- A validating compiler that emits the existing still-export parameters (`ImageFormat` and `ImageExporter` scale/downscale inputs), `MediaExportPreset`, or `GIFExportSettings`. It contains no image, video, or GIF rendering implementation.
- Deterministic dimension, quality, frame-rate, palette, and safe-file-name validation.
- A ShareSafe precondition that fails closed for privacy-required recipes when review was not performed or failed.
- Content-free audit result metadata: recipe ID, opaque privacy-review ID, destination kind, and byte count. File names, OCR text, images, and media are not retained.
- Typed file/Finder, clipboard, drag, share-sheet, and explicitly configured user-owned HTTPS endpoint requests.
- Endpoint validation rejects plaintext HTTP, embedded credentials, and header injection. Compiling an endpoint request performs no network operation and requires no account or hosted Aeroshot service.

## Automated coverage

`AeroshotTests/ExportRecipeTests.swift` covers:

- Stable preset order and Codable round trips.
- Documentation/downscaled/social dimensions and safe naming.
- Direct compilation to still, media, and GIF exporter inputs.
- Fail-closed privacy review and content-free audit metadata.
- Destination availability plus clipboard/share-sheet request metadata.
- HTTPS/user-owned endpoint validation and offline request compilation.

## Validation evidence

- Red test run: new test target initially had no recipe symbols, as expected.
- WP-08 focused suite passed all 8 tests:
  `xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests/ExportRecipeTests CODE_SIGNING_ALLOWED=NO`
- Complete `AeroshotTests` unit-test target passed:
  `xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' -only-testing:AeroshotTests CODE_SIGNING_ALLOWED=NO`
- Independent app build passed:
  `xcodebuild build -project Aeroshot.xcodeproj -scheme Aeroshot -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- Swift 6 compilation, App Intents metadata extraction, linking, and app validation all completed successfully.

## Manual limitations

- An `NSSharingServicePicker` must be presented from a live app/window and cannot be meaningfully asserted by a headless unit test. WP-08 verifies the share-sheet item URL and marks presentation as requiring user interaction; app-level presentation remains a manual integration check.
- Drag initiation likewise needs a live `NSDraggingSession`; the request metadata and availability state are covered, but pointer-driven drag behavior remains manual.
- User-owned endpoint execution is deliberately outside this controller. Tests validate an offline HTTPS request description only; an explicitly authorized caller must attach the local file and perform the URLSession request. No external endpoint was contacted during validation.
- Clipboard request metadata is unit tested. A real general-pasteboard round trip depends on the logged-in macOS pasteboard server and remains an app-level smoke test.

## Gate status

Gate satisfied: compilation and failure behavior are deterministic and explicit, rendering is not duplicated, operation remains local/offline, privacy-required exports fail closed, the complete unit-test target passes, and the app builds successfully.
