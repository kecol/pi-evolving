#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ $# -eq 0 ]] || qwen_die "Usage: ./scripts/models/qwen3.8-27b/download.sh"
qwen_load_profile
qwen_require hf 'Hugging Face CLI not found. Install it with: python -m pip install -U "huggingface_hub[cli]"'

[[ "$MODEL_QUANT" == "UD-Q4_K_XL" ]] || \
  qwen_die "This first-run profile requires the quantized UD-Q4_K_XL model; found $MODEL_QUANT."

printf 'Downloading %s (%s) to %s\n' "$HF_MODEL_REPO" "$MODEL_QUANT" "$MODEL_DIR"
mkdir -p "$MODEL_DIR"
hf download "$HF_MODEL_REPO" \
  --local-dir "$MODEL_DIR" \
  --include "*$MODEL_QUANT*"

[[ -f "$MODEL_FILE" ]] || qwen_die "Expected GGUF was not downloaded: $MODEL_FILE"
printf '\nQuantized model ready: %s\n' "$MODEL_FILE"
