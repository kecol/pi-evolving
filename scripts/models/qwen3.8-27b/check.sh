#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

smoke_test=0
case "${1:-}" in
  "") ;;
  --smoke-test) smoke_test=1 ;;
  *) qwen_die "Usage: ./scripts/models/qwen3.8-27b/check.sh [--smoke-test]" ;;
esac

qwen_require curl "curl is required to check llama-server."
qwen_load_profile
qwen_require_profile_port

base_url="${QWEN38_HOST_BASE_URL:-http://localhost:$LLAMA_ARG_PORT/v1}"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT
curl_args=(
  --fail --silent --show-error --max-time 10
  --header "Authorization: Bearer $LLAMA_API_KEY"
)

printf 'Checking Qwen3.8 llama.cpp endpoint at %s/models\n' "$base_url"
if ! curl "${curl_args[@]}" "$base_url/models" > "$response_file"; then
  qwen_die "Qwen3.8 llama-server is unavailable. Start ./scripts/models/qwen3.8-27b/serve.sh in another shell."
fi

if ! grep -Eq '"id"[[:space:]]*:[[:space:]]*"'"$LLAMA_ARG_ALIAS"'"' "$response_file"; then
  qwen_die "Endpoint responded, but model alias $LLAMA_ARG_ALIAS was not listed."
fi
printf 'Found model alias: %s\n' "$LLAMA_ARG_ALIAS"

if [[ "$smoke_test" == 1 ]]; then
  printf 'Running a short completion smoke test\n'
  payload=$(printf \
    '{"model":"%s","messages":[{"role":"user","content":"Reply with ready."}],"max_tokens":8}' \
    "$LLAMA_ARG_ALIAS")
  curl --fail --silent --show-error --max-time 120 \
    --header "Authorization: Bearer $LLAMA_API_KEY" \
    --header 'Content-Type: application/json' \
    --data "$payload" \
    "$base_url/chat/completions" > "$response_file"
  grep -q '"choices"' "$response_file" || qwen_die "Completion response did not contain choices."
  printf 'Completion smoke test passed\n'
fi
