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
SWIFT_CACHE="${BUILD_ROOT}/module-cache"
VERSION="${ZT_UI_VERSION:-0.1.0}"
SDK_PATH="$(xcrun --show-sdk-path)"

if [[ "${ZT_UI_UNIVERSAL:-}" == "1" ]]; then
  ARCHS=(arm64 x86_64)
else
  ARCHS=("$(uname -m)")
fi

mkdir -p "${BUILD_ROOT}" "${SWIFT_CACHE}"

zig_target_for() {
  case "$1" in
    arm64) printf '%s\n' "aarch64-macos" ;;
    x86_64) printf '%s\n' "x86_64-macos" ;;
    *)
      echo "unsupported macOS arch: $1" >&2
      exit 1
      ;;
  esac
}

swift_target_for() {
  case "$1" in
    arm64) printf '%s\n' "arm64-apple-macosx13.0" ;;
    x86_64) printf '%s\n' "x86_64-apple-macosx13.0" ;;
    *)
      echo "unsupported macOS arch: $1" >&2
      exit 1
      ;;
  esac
}

build_arch() {
  local arch="$1"
  local prefix="${BUILD_ROOT}/zig-${arch}"
  local bin_dir="${BUILD_ROOT}/bins/${arch}"
  mkdir -p "${bin_dir}"

  zig build -Doptimize=ReleaseSafe -Dtarget="$(zig_target_for "${arch}")" --prefix "${prefix}"

  swiftc \
    -target "$(swift_target_for "${arch}")" \
    -sdk "${SDK_PATH}" \
    -module-cache-path "${SWIFT_CACHE}" \
    -framework AppKit \
    -framework WebKit \
    "${ROOT_DIR}/macos/zt-ui-desktop/main.swift" \
    "${ROOT_DIR}/macos/zt-ui-desktop/AppDelegate.swift" \
    "${ROOT_DIR}/macos/zt-ui-desktop/ServerController.swift" \
    -o "${bin_dir}/zt-ui-desktop"

  cp "${prefix}/bin/zt-ui-serve" "${bin_dir}/zt-ui-serve"
  cp "${prefix}/bin/app.wasm" "${BUILD_ROOT}/app.wasm"
}

for arch in "${ARCHS[@]}"; do
  build_arch "${arch}"
done

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

if [[ "${#ARCHS[@]}" -eq 1 ]]; then
  cp "${BUILD_ROOT}/bins/${ARCHS[0]}/zt-ui-desktop" "${MACOS_DIR}/zt-ui-desktop"
  cp "${BUILD_ROOT}/bins/${ARCHS[0]}/zt-ui-serve" "${RESOURCES_DIR}/zt-ui-serve"
else
  lipo -create \
    "${BUILD_ROOT}/bins/arm64/zt-ui-desktop" \
    "${BUILD_ROOT}/bins/x86_64/zt-ui-desktop" \
    -output "${MACOS_DIR}/zt-ui-desktop"
  lipo -create \
    "${BUILD_ROOT}/bins/arm64/zt-ui-serve" \
    "${BUILD_ROOT}/bins/x86_64/zt-ui-serve" \
    -output "${RESOURCES_DIR}/zt-ui-serve"
fi

chmod +x "${MACOS_DIR}/zt-ui-desktop" "${RESOURCES_DIR}/zt-ui-serve"

cp "${ROOT_DIR}/macos/zt-ui-desktop/Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${CONTENTS_DIR}/Info.plist"

cp -R "${ROOT_DIR}/web" "${RESOURCES_DIR}/web"
cp "${BUILD_ROOT}/app.wasm" "${RESOURCES_DIR}/web/app.wasm"

codesign --force --sign - "${RESOURCES_DIR}/zt-ui-serve"
codesign --force --sign - "${MACOS_DIR}/zt-ui-desktop"
codesign --force --sign - "${APP_BUNDLE}"

if [[ -n "${ZT_UI_MACOS_ZIP:-}" ]]; then
  mkdir -p "$(dirname "${ZT_UI_MACOS_ZIP}")"
  rm -f "${ZT_UI_MACOS_ZIP}"
  ditto -c -k --keepParent "${APP_BUNDLE}" "${ZT_UI_MACOS_ZIP}"
  echo "Built ${ZT_UI_MACOS_ZIP}"
else
  echo "Built ${APP_BUNDLE}"
fi
