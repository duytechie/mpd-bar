#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

APP_NAME="MPD Bar"
BUNDLE_DIR="${PWD}/dist/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

export CLANG_MODULE_CACHE_PATH="${PWD}/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PWD}/.build/swiftpm-module-cache"

swift build \
    --disable-sandbox \
    --manifest-cache local \
    -c release \
    --arch arm64 \
    -debug-info-format none \
    --product MPDBar

BIN_DIR="$(swift build \
    --disable-sandbox \
    --manifest-cache local \
    -c release \
    --arch arm64 \
    -debug-info-format none \
    --show-bin-path)"

mkdir -p "${MACOS_DIR}"
cp "${BIN_DIR}/MPDBar" "${MACOS_DIR}/MPDBar"
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

codesign --force --sign - --timestamp=none "${BUNDLE_DIR}"
echo "Built ${BUNDLE_DIR}"
