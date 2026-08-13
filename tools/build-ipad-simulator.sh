#!/usr/bin/env bash
# Build and launch Documents-opensource on a Mac's iPad Simulator.
# Simulator builds deliberately have code signing disabled: Apple signing is not
# needed for a simulator.  For physical device signing, use Xcode with your own
# DEVELOPMENT_TEAM and a unique bundle identifier; do not put either in this repo.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKSPACE="$ROOT/ONLYOFFICE-Documents-opensource.xcworkspace"
SCHEME=Documents-opensource
PACKAGE_URL=https://github.com/my-onlyoffice-forks/editors-ios-sp.git
PACKAGE_REVISION=3f9fd21458ccdd0f528a048f81307d57111d7460
PACKAGE_DIR=${ONLYOFFICE_PACKAGE_DIR:-"$ROOT/.local-artifacts/editors-ios-sp-v9.1"}
ARTIFACT_DIR=${ONLYOFFICE_ARTIFACT_DIR:-"$HOME/Library/Caches/ONLYOFFICE/editors-v9.1.0-179"}
DERIVED_DATA=${DERIVED_DATA:-"$ROOT/.local-artifacts/DerivedData"}
SIMULATOR_NAME=${SIMULATOR_NAME:-"ONLYOFFICE iPad test"}
SIMULATOR_DEVICE=${SIMULATOR_DEVICE:-"iPad Pro 13-inch (M4)"}
BUNDLE_ID=${BUNDLE_ID:-"com.onlyoffice.Documents.opensource"}
BUILD_ONLY=${BUILD_ONLY:-0}

[[ $(uname -s) == Darwin ]] || { echo "ERROR: Xcode and iOS Simulator require a macOS host." >&2; exit 2; }
command -v xcodebuild >/dev/null || { echo "ERROR: Install Xcode from Apple, then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2; exit 2; }
command -v xcrun >/dev/null || { echo "ERROR: xcrun unavailable; select a complete Xcode installation." >&2; exit 2; }
[[ -d "$WORKSPACE" ]] || { echo "ERROR: workspace not found: $WORKSPACE" >&2; exit 2; }

# Use only the declared public package source at its known immutable commit.
if [[ ! -d "$PACKAGE_DIR/.git" ]]; then
  git clone "$PACKAGE_URL" "$PACKAGE_DIR"
fi
git -C "$PACKAGE_DIR" fetch --tags origin
git -C "$PACKAGE_DIR" checkout --detach "$PACKAGE_REVISION"
[[ $(git -C "$PACKAGE_DIR" rev-parse HEAD) == "$PACKAGE_REVISION" ]] || { echo "ERROR: package revision mismatch" >&2; exit 2; }

# This downloads all 22 declared ZIP archives and retains each only if the
# Package.swift SHA-256 matches. SwiftPM/Xcode independently rechecks these
# same declared checksums while resolving binaryTarget dependencies.
python3 "$ROOT/tools/verify_editor_artifacts.py" \
  --manifest "$PACKAGE_DIR/Package.swift" --directory "$ARTIFACT_DIR" --download

# Install exactly the repository's CocoaPods dependencies, outside global gem paths.
command -v bundle >/dev/null || { echo "ERROR: Ruby Bundler is required (run: gem install --user-install bundler)." >&2; exit 2; }
cd "$ROOT"
bundle config set --local path .local-artifacts/bundle
bundle install
bundle exec pod install

# Resolve the controlled public Swift package before building.
xcodebuild -resolvePackageDependencies -workspace "$WORKSPACE" -scheme "$SCHEME" \
  -clonedSourcePackagesDirPath "$ROOT/.local-artifacts/SourcePackages"

# A simulator app is not signed; do not use the snapshot's former team ID.
# CI uses BUILD_ONLY=1 so it can compile without allocating a GUI simulator.
if [[ "$BUILD_ONLY" == 1 ]]; then
  xcodebuild build -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
    IPHONEOS_DEPLOYMENT_TARGET=14.0
  echo "BUILD_READY"
  echo "App products: $DERIVED_DATA/Build/Products/Debug-iphonesimulator"
  exit 0
fi

# Create and boot an actual iPad simulator for interactive testing.
DEVICE_TYPE=$(xcrun simctl list devicetypes | awk -F '[()]' -v name="$SIMULATOR_DEVICE" '$0 ~ name && $2 ~ /SimDeviceType/ { print $2; exit }')
if [[ -z "$DEVICE_TYPE" ]]; then
  DEVICE_TYPE=$(xcrun simctl list devicetypes | awk -F '[()]' '/iPad/ && $2 ~ /SimDeviceType/ { print $2; exit }')
fi
[[ -n "$DEVICE_TYPE" ]] || { echo "ERROR: no installed iPad Simulator device type. Install an iOS Simulator runtime in Xcode Settings > Components." >&2; exit 2; }

UDID=$(xcrun simctl list devices | awk -v name="$SIMULATOR_NAME" '$0 ~ name { id=$NF; gsub(/[()]/,"",id); print id; exit }')
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun simctl create "$SIMULATOR_NAME" "$DEVICE_TYPE")
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
open -a Simulator

xcodebuild build -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  IPHONEOS_DEPLOYMENT_TARGET=14.0

APP=$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' -type d | head -n 1)
[[ -n "$APP" ]] || { echo "ERROR: built app bundle not found" >&2; exit 2; }
xcrun simctl install "$UDID" "$APP"

# A non-secret local rich-text sample for manual local-file/editor smoke testing.
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
mkdir -p "$CONTAINER/Documents"
printf '{\\rtf1\\ansi ONLYOFFICE iPad simulator smoke test.\\par Local document editor check.\\par}\n' > "$CONTAINER/Documents/ONLYOFFICE-smoke-test.rtf"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "READY"
echo "Simulator UDID: $UDID"
echo "App: $APP"
echo "Smoke-test file: $CONTAINER/Documents/ONLYOFFICE-smoke-test.rtf"
echo "In the app, use the Local Files flow to open ONLYOFFICE-smoke-test.rtf and confirm the native document editor opens."
