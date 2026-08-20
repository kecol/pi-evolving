#!/usr/bin/env bash

set -euo pipefail

QWEN_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
QWEN_REPO_ROOT="$(cd -- "$QWEN_SCRIPT_DIR/../../.." && pwd)"
QWEN_PROFILE_TEMPLATE="$QWEN_REPO_ROOT/models/qwen3.8-27b/model.env.example"
QWEN_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/pi-evolving/models"
QWEN_PROFILE_FILE="${QWEN38_PROFILE_FILE:-$QWEN_CONFIG_HOME/qwen3.8-27b.env}"

qwen_die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

qwen_require() {
  command -v "$1" >/dev/null 2>&1 || qwen_die "$2"
}

qwen_load_profile() {
  if [[ ! -f "$QWEN_PROFILE_FILE" ]]; then
    mkdir -p "$(dirname -- "$QWEN_PROFILE_FILE")"
    cp "$QWEN_PROFILE_TEMPLATE" "$QWEN_PROFILE_FILE"
    printf 'Created %s\n' "$QWEN_PROFILE_FILE"
  fi

  # This is a user-owned shell profile whose purpose is to export model and
  # llama-server settings.
  # shellcheck disable=SC1090
  source "$QWEN_PROFILE_FILE"

  : "${HF_MODEL_REPO:?HF_MODEL_REPO is required in $QWEN_PROFILE_FILE}"
  : "${MODEL_QUANT:?MODEL_QUANT is required in $QWEN_PROFILE_FILE}"
  : "${MODEL_DIR:?MODEL_DIR is required in $QWEN_PROFILE_FILE}"
  : "${MODEL_FILE:?MODEL_FILE is required in $QWEN_PROFILE_FILE}"
  : "${LLAMA_ARG_ALIAS:?LLAMA_ARG_ALIAS is required in $QWEN_PROFILE_FILE}"
  : "${LLAMA_ARG_PORT:?LLAMA_ARG_PORT is required in $QWEN_PROFILE_FILE}"
  : "${LLAMA_API_KEY:?LLAMA_API_KEY is required in $QWEN_PROFILE_FILE}"
}
