#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="zt-ui Desktop.app"
BUILD_ROOT="${ROOT_DIR}/dist/macos-app"
APP_BUNDLE="${BUILD_ROOT}/${APP_NAME}"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ZIG_PREFIX="${BUILD_ROOT}/zig-prefix"
SWIFT_CACHE="${BUILD_ROOT}/module-cache"

mkdir -p "${BUILD_ROOT}" "${SWIFT_CACHE}"

zig build -Doptimize=ReleaseSafe --prefix "${ZIG_PREFIX}"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

swiftc \
  -module-cache-path "${SWIFT_CACHE}" \
  -framework AppKit \
  -framework WebKit \
  "${ROOT_DIR}/macos/zt-ui-desktop/main.swift" \
  "${ROOT_DIR}/macos/zt-ui-desktop/AppDelegate.swift" \
  "${ROOT_DIR}/macos/zt-ui-desktop/ServerController.swift" \
  -o "${MACOS_DIR}/zt-ui-desktop"

cp "${ROOT_DIR}/macos/zt-ui-desktop/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ZIG_PREFIX}/bin/zt-ui-serve" "${RESOURCES_DIR}/zt-ui-serve"
chmod +x "${RESOURCES_DIR}/zt-ui-serve"

cp -R "${ROOT_DIR}/web" "${RESOURCES_DIR}/web"
cp "${ZIG_PREFIX}/bin/app.wasm" "${RESOURCES_DIR}/web/app.wasm"

echo "Built ${APP_BUNDLE}"
