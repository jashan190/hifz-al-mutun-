#!/usr/bin/env bash
# Build a signed .ipa for TestFlight — no Xcode GUI needed.
# Afterwards, drag the printed .ipa into the Transporter app and hit Deliver.
#
#   ./Tools/testflight.sh
#
# Remember: App Store Connect rejects a re-used build number. Before each new
# upload, bump CURRENT_PROJECT_VERSION in project.yml, then re-run this script.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="HifzAlMutun.xcodeproj"
SCHEME="HifzAlMutun"
ARCHIVE="build/HifzAlMutun.xcarchive"
IPA_DIR="build/ipa"

echo "==> Regenerating project from project.yml"
xcodegen generate

echo "==> Archiving (Release, generic iOS device)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE"

echo "==> Exporting signed .ipa"
rm -rf "$IPA_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "$IPA_DIR"

echo
echo "==> Done. Drop this file into Transporter:"
ls -1 "$PWD/$IPA_DIR"/*.ipa
