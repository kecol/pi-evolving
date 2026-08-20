#!/usr/bin/env bash
set -euo pipefail

template=/tmp/pi-evolving-models.json
destination=/home/pi/.pi-agent/models.json

jq empty "$template"
base_url=$(jq -r '.providers["llamacpp-wsl"].baseUrl' "$template")
api_key=$(jq -r '.providers["llamacpp-wsl"].apiKey // empty' "$template")
auth_header=$(jq -r '.providers["llamacpp-wsl"].authHeader // false' "$template")
model_id=$(jq -r '.providers["llamacpp-wsl"].models[0].id' "$template")

if [[ "${PI_SKIP_LOCAL_MODEL_CHECK:-0}" != 1 ]]; then
  echo "Checking llama.cpp at $base_url/models"
  curl_args=(--fail --silent --show-error --max-time 10)
  if [[ "$auth_header" == true && -n "$api_key" ]]; then
    curl_args+=(--header "Authorization: Bearer $api_key")
  fi
  models_response=$(mktemp)
  completion_response=$(mktemp)
  trap 'rm -f "$models_response" "$completion_response"' EXIT
  if ! curl "${curl_args[@]}" "$base_url/models" > "$models_response"; then
    echo "Error: llama.cpp is not reachable from the container." >&2
    echo "Start llama-server with --host 0.0.0.0 --port 8080, then retry." >&2
    echo "Use --skip-check only if you intentionally want to install the preset while the server is offline." >&2
    exit 1
  fi
  if ! jq -e --arg model "$model_id" 'any(.data[]?; .id == $model)' "$models_response" >/dev/null; then
    echo "Error: llama.cpp responded, but model alias '$model_id' was not listed." >&2
    exit 1
  fi

  if [[ "${PI_LOCAL_MODEL_SMOKE_TEST:-0}" == 1 ]]; then
    echo "Running a completion smoke test with $model_id"
    payload=$(jq -nc --arg model "$model_id" \
      '{model:$model,messages:[{role:"user",content:"Reply with ready."}],max_tokens:8}')
    completion_curl_args=(--fail --silent --show-error --max-time 120)
    if [[ "$auth_header" == true && -n "$api_key" ]]; then
      completion_curl_args+=(--header "Authorization: Bearer $api_key")
    fi
    if ! curl "${completion_curl_args[@]}" \
      --header 'Content-Type: application/json' \
      --data "$payload" \
      "$base_url/chat/completions" > "$completion_response"; then
      echo "Error: llama.cpp completion smoke test failed." >&2
      exit 1
    fi
    if ! jq -e '.choices | type == "array" and length > 0' "$completion_response" >/dev/null; then
      echo "Error: llama.cpp returned no completion choices." >&2
      exit 1
    fi
    echo "Completion smoke test passed"
  fi
fi

if [[ -f "$destination" ]] && ! cmp -s "$destination" "$template"; then
  backup="/home/pi/.pi-agent/models.backup.$(date -u +%Y%m%dT%H%M%SZ).json"
  cp "$destination" "$backup"
  chmod 600 "$backup"
  echo "Preserved existing model configuration at $backup"
fi

install -m 600 "$template" "$destination"
echo "Installed llama.cpp model configuration at $destination"
