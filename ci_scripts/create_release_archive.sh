#!/bin/zsh

set -euo pipefail

PROJECT="${PROJECT:-LanguageLearning.xcodeproj}"
SCHEME="${SCHEME:-LanguageLearning}"
ARCHIVE_TEMP_DIRECTORY=""
if [[ -z "${ARCHIVE_PATH:-}" ]]; then
  ARCHIVE_TEMP_DIRECTORY=$(mktemp -d /tmp/CueFlow-Archive.XXXXXX)
  ARCHIVE_PATH="$ARCHIVE_TEMP_DIRECTORY/CueFlow.xcarchive"
fi

if [[ ! -d "$PROJECT" ]]; then
  xcodegen generate
fi

if [[ -e "$ARCHIVE_PATH" ]]; then
  echo "Refusing to overwrite existing archive: $ARCHIVE_PATH"
  exit 4
fi
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH"

echo "Archive created at $ARCHIVE_PATH"
echo "Upload remains an explicit App Store Connect action."
