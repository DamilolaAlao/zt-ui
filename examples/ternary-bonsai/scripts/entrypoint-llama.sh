#!/bin/sh
# Ensure model exists, then start PrismML llama-server (Q2_0 / ternary kernels).
set -eu

MODELS_DIR="${MODELS_DIR:-/models}"
MODEL_FILE="${MODEL_FILE:-Ternary-Bonsai-1.7B-Q2_0.gguf}"
MODEL_PATH="${MODELS_DIR}/${MODEL_FILE}"
LLAMA_HOST="${LLAMA_HOST:-0.0.0.0}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
LLAMA_CTX="${LLAMA_CTX:-2048}"
LLAMA_THREADS="${LLAMA_THREADS:-$(nproc 2>/dev/null || echo 4)}"
LLAMA_NGL="${LLAMA_NGL:-0}"

/usr/local/bin/download-model.sh

echo "starting llama-server"
echo "  model=${MODEL_PATH}"
echo "  host=${LLAMA_HOST}:${LLAMA_PORT} ctx=${LLAMA_CTX} threads=${LLAMA_THREADS} ngl=${LLAMA_NGL}"

exec /opt/llama/llama-server \
  -m "${MODEL_PATH}" \
  --host "${LLAMA_HOST}" \
  --port "${LLAMA_PORT}" \
  -c "${LLAMA_CTX}" \
  -t "${LLAMA_THREADS}" \
  -ngl "${LLAMA_NGL}" \
  --jinja
