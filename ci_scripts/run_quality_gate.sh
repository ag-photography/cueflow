#!/bin/zsh

set -euo pipefail

PROJECT="${PROJECT:-LanguageLearning.xcodeproj}"
SCHEME="${SCHEME:-LanguageLearning}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
QUALITY_TEMP_DIRECTORY=""
if [[ -z "${RESULT_BUNDLE:-}" ]]; then
  QUALITY_TEMP_DIRECTORY=$(mktemp -d /tmp/CueFlow-Quality.XXXXXX)
  RESULT_BUNDLE="$QUALITY_TEMP_DIRECTORY/results.xcresult"
fi
MIN_APP_COVERAGE="${MIN_APP_COVERAGE:-14.0}"

if [[ ! -d "$PROJECT" ]]; then
  xcodegen generate
fi

# Fail fast on coherence drift (docs/coherence.md) before the long test run.
"$(dirname "$0")/coherence_ratchet.sh"

if [[ -e "$RESULT_BUNDLE" ]]; then
  echo "Refusing to overwrite existing result bundle: $RESULT_BUNDLE"
  exit 4
fi
# UI checks change orientation, keyboard and accessibility size. Default to a
# single runner for reproducibility; CI can explicitly opt into parallel runs.
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -parallel-testing-enabled "${PARALLEL_TESTING_ENABLED:-NO}" \
  -collect-test-diagnostics "${COLLECT_TEST_DIAGNOSTICS:-on-failure}" \
  -resultBundlePath "$RESULT_BUNDLE"

APP_COVERAGE=$(xcrun xccov view --report "$RESULT_BUNDLE" \
  | awk '$1 == "LanguageLearning.app" { gsub("%", "", $2); print $2; exit }')

if [[ -z "$APP_COVERAGE" ]]; then
  echo "Could not read LanguageLearning.app coverage"
  exit 2
fi

if (( $(printf '%s < %s\n' "$APP_COVERAGE" "$MIN_APP_COVERAGE" | bc -l) )); then
  echo "Coverage regression: ${APP_COVERAGE}% < ${MIN_APP_COVERAGE}%"
  exit 3
fi

echo "Quality gate passed with ${APP_COVERAGE}% app coverage"
