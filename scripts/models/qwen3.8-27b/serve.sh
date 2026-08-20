#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ $# -eq 0 ]] || qwen_die "Usage: ./scripts/models/qwen3.8-27b/serve.sh"
qwen_require llama-server "llama-server not found on PATH. Follow docs/LLAMA_CPP.md first."
qwen_load_profile

[[ "$MODEL_QUANT" == "UD-Q4_K_XL" ]] || \
  qwen_die "This first-run profile requires the quantized UD-Q4_K_XL model; found $MODEL_QUANT."
[[ -f "$MODEL_FILE" ]] || \
  qwen_die "Model file not found: $MODEL_FILE. Run ./scripts/models/qwen3.8-27b/download.sh first."

printf 'Starting Qwen3.8-27B %s as %s on port %s\n' \
  "$MODEL_QUANT" "$LLAMA_ARG_ALIAS" "$LLAMA_ARG_PORT"
exec llama-server \
  --temp "$LOCAL_MODEL_TEMPERATURE" \
  --top-p "$LOCAL_MODEL_TOP_P" \
  --top-k "$LOCAL_MODEL_TOP_K" \
  --min-p "$LOCAL_MODEL_MIN_P"
