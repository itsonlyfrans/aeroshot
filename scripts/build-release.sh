#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
release_dir="${AEROSHOT_RELEASE_DIR:-$repo_root/build/release}"
archive_path="$release_dir/Aeroshot.xcarchive"
execute=false

case "${1:-}" in
  "") ;;
  --execute) execute=true ;;
  --help|-h)
    print "usage: scripts/build-release.sh [--execute]"
    print "Default is a safe dry run. --execute tests and archives only."
    exit 0
    ;;
  *) print -u2 "unknown argument: $1"; exit 64 ;;
esac

planned_commands=(
  "xcodebuild test -project Aeroshot.xcodeproj -scheme Aeroshot -destination platform=macOS -only-testing:AeroshotTests CODE_SIGNING_ALLOWED=NO"
  "xcodebuild archive -project Aeroshot.xcodeproj -scheme Aeroshot -configuration Release -destination generic/platform=macOS -archivePath ${(q)archive_path}"
  "scripts/verify-release.sh ${(q)archive_path}/Products/Applications/Aeroshot.app"
)

print "Aeroshot release preparation"
print "Repository: $repo_root"
print "Archive:    $archive_path"
print "Scope: unit test + local archive + inspection; no export/upload/notarization/publication"

if ! $execute; then
  print "DRY RUN (pass --execute to run the first two commands):"
  for command in $planned_commands; do print "  $command"; done
  exit 0
fi

mkdir -p "$release_dir"
cd "$repo_root"
xcodebuild test \
  -project Aeroshot.xcodeproj \
  -scheme Aeroshot \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:AeroshotTests \
  CODE_SIGNING_ALLOWED=NO
xcodebuild archive \
  -project Aeroshot.xcodeproj \
  -scheme Aeroshot \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path"

print "Archive created. Inspect it with:"
print "  scripts/verify-release.sh ${(q)archive_path}/Products/Applications/Aeroshot.app"
print "Export, Developer ID signing, notarization, stapling, and publication remain manual credential-gated steps."
