# Building Aeroshot

## Requirements

- macOS 14.6 or later
- The Xcode version selected by `xcode-select`
- Command Line Tools accepted and available

The project has no downloaded runtime dependencies. From a clean checkout:

```sh
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Use `scripts/build-release.sh` for the documented release path. It is a dry run
unless passed `--execute`; its output directory defaults to `build/release` and
can be overridden with `AEROSHOT_RELEASE_DIR`. Archive execution intentionally
does not export, notarize, publish, or modify project signing settings.

UI tests require a valid local development signature and Developer Mode. Do not
pass `CODE_SIGNING_ALLOWED=NO` to `scripts/run-ui-tests.sh`: an unsigned
`AeroshotUITests-Runner.app` can produce macOS's misleading “damaged, move to
Trash” alert. Remove stale derived data and rerun after enabling Developer Mode.
