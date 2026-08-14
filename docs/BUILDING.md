# Building Aeroshot

## Requirements

- macOS 14.6 or later
- The Xcode version selected by `xcode-select`
- Command Line Tools accepted and available
- Node.js 22.12 or later and pnpm 11.20 for the website

Xcode resolves the pinned Swift packages from `Package.resolved`. A clean
checkout needs network access or an existing Swift package cache. Run:

```sh
xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -only-testing:AeroshotTests \
  CODE_SIGNING_ALLOWED=NO
```

Build the website from the repository root:

```sh
pnpm install --frozen-lockfile
pnpm website:build
```

Use `scripts/build-release.sh` for the documented release path. It is a dry run
unless passed `--execute`; its output directory defaults to `build/release` and
can be overridden with `AEROSHOT_RELEASE_DIR`. Archive execution intentionally
does not export, notarize, publish, or modify project signing settings. The
repository stores the shared `Aeroshot` scheme used by each build script.

UI tests require a valid local development signature and Developer Mode. Do not
pass `CODE_SIGNING_ALLOWED=NO` to `scripts/run-ui-tests.sh`: an unsigned
`AeroshotUITests-Runner.app` can produce macOS's misleading “damaged, move to
Trash” alert. Remove stale derived data and rerun after enabling Developer Mode.
