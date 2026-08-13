#!/bin/sh
# Download Ternary-Bonsai-1.7B Q2_0 GGUF into MODELS_DIR if missing.
set -eu

MODELS_DIR="${MODELS_DIR:-/models}"
MODEL_REPO="${MODEL_REPO:-prism-ml/Ternary-Bonsai-1.7B-gguf}"
MODEL_FILE="${MODEL_FILE:-Ternary-Bonsai-1.7B-Q2_0.gguf}"
MODEL_PATH="${MODELS_DIR}/${MODEL_FILE}"
URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"

mkdir -p "${MODELS_DIR}"

if [ -f "${MODEL_PATH}" ] && [ "$(wc -c < "${MODEL_PATH}")" -gt 100000000 ]; then
  echo "model already present: ${MODEL_PATH}"
  exit 0
fi

echo "downloading ${MODEL_FILE} (~442 MB) from Hugging Face…"
echo "  ${URL}"
tmp="${MODEL_PATH}.partial"
rm -f "${tmp}"

if command -v curl >/dev/null 2>&1; then
  curl -L --fail --retry 3 --retry-delay 2 --progress-bar \
    -o "${tmp}" "${URL}?download=true"
elif command -v wget >/dev/null 2>&1; then
  wget -O "${tmp}" "${URL}?download=true"
else
  echo "need curl or wget to download the model" >&2
  exit 1
fi

size="$(wc -c < "${tmp}")"
if [ "${size}" -lt 100000000 ]; then
  echo "download looks truncated (${size} bytes); refusing to install" >&2
  rm -f "${tmp}"
  exit 1
fi

mv "${tmp}" "${MODEL_PATH}"
echo "saved ${MODEL_PATH} (${size} bytes)"
