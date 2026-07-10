# WP-09 UI-test runner triage

**Status:** resolved on the reference machine

## Failure classification

The UI runner failure was a host/tooling setup issue, not an app assertion failure:

- Existing generated `AeroshotUITests-Runner.app` was Apple Development signed and passed strict `codesign` verification.
- Gatekeeper assessment rejected the development runner and it carried `com.apple.provenance` metadata.
- A fresh signed runner launched, then initially failed with `Timed out while enabling automation mode`.
- `DevToolsSecurity -status` reported Developer Mode disabled.

## Resolution

`DevToolsSecurity -enable` enabled Developer Mode. The same freshly signed runner then initialized automation and passed the focused UI test.

Do not run the unfiltered scheme with `CODE_SIGNING_ALLOWED=NO`: that setting is appropriate for the unit-only target but invalidates the generated UI runner's execution path. Use `scripts/run-ui-tests.sh`, which checks Developer Mode and preserves signing.

## Passing evidence

```sh
xcodebuild test-without-building \
  -project Aeroshot.xcodeproj \
  -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/aeroshot-ui-runner-dd \
  -only-testing:AeroshotUITests/AeroshotUITests/testExample
```

Result: **1 test executed, 0 failures, `TEST EXECUTE SUCCEEDED`** in 2.523 seconds.

This proves runner launch and automation initialization on the reference machine. It does not replace later golden-workflow UI coverage or permission-matrix testing.
