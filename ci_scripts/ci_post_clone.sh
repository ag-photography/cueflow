#!/bin/sh
# Xcode Cloud post-clone hook.
#
# Runs in Apple's macOS build image after the repo is checked out, before
# Xcode is invoked. We use it to install xcodegen and regenerate the .xcodeproj
# from project.yml (which is the committed source of truth — the .xcodeproj
# itself is git-ignored).
#
# Docs: https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -euo pipefail

echo "==> Installing xcodegen via Homebrew"
brew install xcodegen

echo "==> Regenerating Xcode project from project.yml"
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "==> Done"
