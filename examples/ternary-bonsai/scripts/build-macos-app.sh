#!/usr/bin/env bash
# Build zt-ui Ternary Bonsai.app — MLX (Apple Silicon) + Node bridge + zt-ui.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${EXAMPLE_DIR}/../.." && pwd)"

APP_NAME="zt-ui Ternary Bonsai.app"
BUILD_ROOT="${ROOT_DIR}/dist/macos-ternary-bonsai"
APP_BUNDLE="${BUILD_ROOT}/${APP_NAME}"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
VENDOR_DIR="${BUILD_ROOT}/vendor"
ZIG_PREFIX="${BUILD_ROOT}/zig-prefix"
SWIFT_CACHE="${BUILD_ROOT}/module-cache"

NODE_VERSION="${NODE_VERSION:-22.14.0}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

ARCH="$(uname -m)"
case "${ARCH}" in
  arm64)
    NODE_ARCH="darwin-arm64"
    ;;
  *)
    echo "Ternary-Bonsai MLX desktop requires Apple Silicon (arm64). Got: ${ARCH}" >&2
    exit 1
    ;;
esac

mkdir -p "${BUILD_ROOT}" "${VENDOR_DIR}" "${SWIFT_CACHE}"

echo "==> building zt-ui (zig)"
zig build -Doptimize=ReleaseSafe --prefix "${ZIG_PREFIX}"

echo "==> fetching Node ${NODE_VERSION} (${NODE_ARCH})"
NODE_TGZ="${VENDOR_DIR}/node-v${NODE_VERSION}-${NODE_ARCH}.tar.gz"
if [[ ! -f "${NODE_TGZ}" ]]; then
  curl -fL --retry 3 -o "${NODE_TGZ}" \
    "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${NODE_ARCH}.tar.gz"
fi
rm -rf "${VENDOR_DIR}/node-extract"
mkdir -p "${VENDOR_DIR}/node-extract"
tar -xzf "${NODE_TGZ}" -C "${VENDOR_DIR}/node-extract"
NODE_SRC="$(find "${VENDOR_DIR}/node-extract" -type d -name "node-v${NODE_VERSION}-${NODE_ARCH}" | head -n 1)"
test -n "${NODE_SRC}"
test -x "${NODE_SRC}/bin/node"

echo "==> creating MLX venv (mlx-lm + huggingface_hub)"
MLX_VENV="${VENDOR_DIR}/mlx-venv"
if [[ ! -x "${MLX_VENV}/bin/python" ]]; then
  rm -rf "${MLX_VENV}"
  "${PYTHON_BIN}" -m venv "${MLX_VENV}"
  "${MLX_VENV}/bin/pip" install --upgrade pip
  "${MLX_VENV}/bin/pip" install "mlx-lm" "huggingface_hub"
fi
"${MLX_VENV}/bin/python" -c "import mlx_lm, huggingface_hub; print('mlx-lm ok')"

echo "==> preparing bridge package"
BRIDGE_STAGE="${BUILD_ROOT}/bridge-stage"
rm -rf "${BRIDGE_STAGE}"
mkdir -p "${BRIDGE_STAGE}"
cp "${EXAMPLE_DIR}/bridge/package.json" "${BRIDGE_STAGE}/"
cp -R "${EXAMPLE_DIR}/bridge/src" "${BRIDGE_STAGE}/src"
cp -R "${EXAMPLE_DIR}/bridge/public" "${BRIDGE_STAGE}/public"
(
  cd "${BRIDGE_STAGE}"
  npm install --omit=dev
)

echo "==> assembling ${APP_NAME}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}/node" "${RESOURCES_DIR}/bridge"

swiftc \
  -module-cache-path "${SWIFT_CACHE}" \
  -framework AppKit \
  -framework WebKit \
  "${ROOT_DIR}/macos/ternary-bonsai-desktop/main.swift" \
  "${ROOT_DIR}/macos/ternary-bonsai-desktop/AppDelegate.swift" \
  "${ROOT_DIR}/macos/ternary-bonsai-desktop/StackController.swift" \
  -o "${MACOS_DIR}/zt-ui-ternary-bonsai"

cp "${ROOT_DIR}/macos/ternary-bonsai-desktop/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Copy MLX venv (large). Prefer rsync to preserve symlinks from venv.
rm -rf "${RESOURCES_DIR}/mlx-venv"
rsync -a "${MLX_VENV}/" "${RESOURCES_DIR}/mlx-venv/"
# Rewrite venv shebangs / pyvenv.cfg home to the bundled path is fragile at
# runtime; launch via absolute python binary path from StackController instead.
chmod +x "${RESOURCES_DIR}/mlx-venv/bin/python" "${RESOURCES_DIR}/mlx-venv/bin/python3" 2>/dev/null || true

cp -a "${NODE_SRC}/." "${RESOURCES_DIR}/node/"
chmod +x "${RESOURCES_DIR}/node/bin/node"

cp -R "${BRIDGE_STAGE}/." "${RESOURCES_DIR}/bridge/"

cp "${ZIG_PREFIX}/bin/zt-ui-serve" "${RESOURCES_DIR}/zt-ui-serve"
chmod +x "${RESOURCES_DIR}/zt-ui-serve"
cp -R "${ROOT_DIR}/web" "${RESOURCES_DIR}/web"
cp "${ZIG_PREFIX}/bin/app.wasm" "${RESOURCES_DIR}/web/app.wasm"

if command -v codesign >/dev/null 2>&1; then
  echo "==> ad-hoc codesign"
  codesign --force --deep --sign - "${APP_BUNDLE}" || true
fi

echo "Built ${APP_BUNDLE}"
echo "Open with: open \"${APP_BUNDLE}\""
echo "First launch downloads prism-ml/Ternary-Bonsai-1.7B-mlx-2bit (~480 MB) into Application Support."
