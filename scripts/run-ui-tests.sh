#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
derived_data="${AEROSHOT_UI_DERIVED_DATA:-/tmp/aeroshot-ui-tests-dd}"
result_bundle="${AEROSHOT_UI_RESULT_BUNDLE:-}"
test_filter="${AEROSHOT_UI_FILTER:-}"

cd "$repo_root"

if ! DevToolsSecurity -status 2>&1 | grep -q "enabled"; then
  print -u2 "Aeroshot UI tests require macOS Developer Mode. Run: DevToolsSecurity -enable"
  exit 2
fi

if [[ " ${*:-} " == *" CODE_SIGNING_ALLOWED=NO "* || " ${*:-} " == *" CODE_SIGNING_REQUIRED=NO "* ]]; then
  print -u2 "Refusing to create an unsigned XCTRunner. Remove CODE_SIGNING_ALLOWED/REQUIRED=NO."
  exit 2
fi

typeset -a test_options
test_options=(-only-testing:AeroshotUITests)
[[ -n "$test_filter" ]] && test_options=(-only-testing:"AeroshotUITests/$test_filter")
if [[ -n "$result_bundle" ]]; then
  rm -rf "$result_bundle"
  test_options+=(-resultBundlePath "$result_bundle")
fi

# UI-test runners must remain signed. CODE_SIGNING_ALLOWED=NO is valid for the
# unit-only command, but makes the generated XCTRunner fail Gatekeeper.
xcodebuild test \
  -project Aeroshot.xcodeproj \
  -scheme Aeroshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  "${test_options[@]}" \
  "$@"
