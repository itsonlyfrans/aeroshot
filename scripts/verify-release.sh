#!/bin/zsh
set -euo pipefail

usage() {
  print "usage: scripts/verify-release.sh [/path/to/Aeroshot.app]"
  print "With no app, validates release inputs without building or publishing."
}

repo_root="${0:A:h:h}"
app_path="${1:-}"
failures=0

check_tool() {
  if command -v "$1" >/dev/null; then
    print "PASS tool: $1"
  else
    print -u2 "FAIL missing tool: $1"
    failures=$((failures + 1))
  fi
}

if [[ "$app_path" == "--help" || "$app_path" == "-h" ]]; then usage; exit 0; fi

cd "$repo_root"
for tool in xcodebuild codesign spctl plutil; do check_tool "$tool"; done

for key in NSScreenCaptureUsageDescription NSCameraUsageDescription NSMicrophoneUsageDescription; do
  if /usr/libexec/PlistBuddy -c "Print :$key" Aeroshot/Info.plist >/dev/null 2>&1; then
    print "PASS privacy description: $key"
  else
    print -u2 "FAIL missing privacy description: $key"
    failures=$((failures + 1))
  fi
done
if grep -q 'plutil -replace LSMultipleInstancesProhibited -bool false' Aeroshot.xcodeproj/project.pbxproj; then
  print "PASS single-instance launch contract"
else
  print -u2 "FAIL single-instance launch contract"
  failures=$((failures + 1))
fi

version=$(xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot -configuration Release -showBuildSettings 2>/dev/null | awk '/ MARKETING_VERSION = / {print $3; exit}')
build=$(xcodebuild -project Aeroshot.xcodeproj -scheme Aeroshot -configuration Release -showBuildSettings 2>/dev/null | awk '/ CURRENT_PROJECT_VERSION = / {print $3; exit}')
if [[ -n "$version" && -n "$build" ]]; then
  print "PASS configured version: $version ($build)"
else
  print -u2 "FAIL unable to read configured version/build"
  failures=$((failures + 1))
fi

if [[ -z "$app_path" ]]; then
  if [[ -n "${AEROSHOT_NOTARY_PROFILE:-}" ]]; then
    print "INPUT notary profile: configured in environment (value redacted)"
  else
    print "INPUT notary profile: not configured (credential-gated)"
  fi
  print "INPUT app artifact: not supplied (artifact checks skipped)"
  (( failures == 0 )) && print "Preflight passed. No artifact was built, signed, submitted, or published."
  exit "$failures"
fi

if [[ ! -d "$app_path" ]]; then print -u2 "FAIL app not found: $app_path"; exit 66; fi

info="$app_path/Contents/Info.plist"
if [[ -f "$info" ]]; then
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info" 2>/dev/null || true)
  artifact_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info" 2>/dev/null || true)
  artifact_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info" 2>/dev/null || true)
  [[ "$bundle_id" == "com.aeroshot" ]] && print "PASS bundle identity: $bundle_id" || { print -u2 "FAIL bundle identity: $bundle_id"; failures=$((failures + 1)); }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMultipleInstancesProhibited' "$info" 2>/dev/null || true)" == "true" ]] && print "PASS artifact single-instance contract" || { print -u2 "FAIL artifact single-instance contract"; failures=$((failures + 1)); }
  [[ -n "$artifact_version" && -n "$artifact_build" ]] && print "PASS artifact version: $artifact_version ($artifact_build)" || { print -u2 "FAIL artifact version/build missing"; failures=$((failures + 1)); }
  for key in NSScreenCaptureUsageDescription NSCameraUsageDescription NSMicrophoneUsageDescription; do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$info" >/dev/null 2>&1; then
      print "PASS artifact privacy description: $key"
    else
      print -u2 "FAIL artifact missing privacy description: $key"
      failures=$((failures + 1))
    fi
  done
else
  print -u2 "FAIL missing app Info.plist"
  failures=$((failures + 1))
fi

if codesign --verify --deep --strict --verbose=2 "$app_path"; then
  print "PASS code signature including nested code"
else
  print -u2 "FAIL code signature"
  failures=$((failures + 1))
fi

signature=$(codesign -dvv "$app_path" 2>&1 || true)
expected_authority="${AEROSHOT_EXPECTED_SIGNING_AUTHORITY:-Developer ID Application:}"
if [[ "$signature" == *"Authority=$expected_authority"* ]]; then
  print "PASS distribution signing authority matches expected prefix"
else
  print -u2 "FAIL expected signing authority prefix '$expected_authority' (override only for non-release inspection with AEROSHOT_EXPECTED_SIGNING_AUTHORITY)"
  failures=$((failures + 1))
fi
if [[ "$signature" == *"flags=0x10000(runtime)"* || "$signature" == *"flags=0x"*"runtime"* ]]; then
  print "PASS hardened runtime"
else
  print -u2 "FAIL hardened runtime not present in signature flags"
  failures=$((failures + 1))
fi

entitlements=$(mktemp -t aeroshot-entitlements)
trap 'rm -f "$entitlements"' EXIT
codesign -d --entitlements :- "$app_path" >"$entitlements" 2>/dev/null || true
if plutil -lint "$entitlements" >/dev/null 2>&1; then
  print "PASS signed entitlements are valid plist data"
  plutil -p "$entitlements"
else
  print "PASS no explicit signed entitlements (reviewed)"
fi

if [[ "${AEROSHOT_REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
  if xcrun stapler validate "$app_path" && spctl --assess --type execute --verbose=2 "$app_path"; then
    print "PASS notarization ticket and Gatekeeper assessment"
  else
    print -u2 "FAIL notarization required but ticket/assessment failed"
    failures=$((failures + 1))
  fi
else
  print "SKIP notarization (set AEROSHOT_REQUIRE_NOTARIZATION=1 after credentialed submission/stapling)"
fi

(( failures == 0 )) && print "Artifact verification passed; nothing was uploaded or published."
exit "$failures"
