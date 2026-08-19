#!/usr/bin/env bash
set -euo pipefail

template=/tmp/pi-evolving-models.json
destination=/home/pi/.pi-agent/models.json

jq empty "$template"
base_url=$(jq -r '.providers["llamacpp-wsl"].baseUrl' "$template")
api_key=$(jq -r '.providers["llamacpp-wsl"].apiKey // empty' "$template")
auth_header=$(jq -r '.providers["llamacpp-wsl"].authHeader // false' "$template")

if [[ "${PI_SKIP_LOCAL_MODEL_CHECK:-0}" != 1 ]]; then
  echo "Checking llama.cpp at $base_url/models"
  curl_args=(--fail --silent --show-error --max-time 10)
  if [[ "$auth_header" == true && -n "$api_key" ]]; then
    curl_args+=(--header "Authorization: Bearer $api_key")
  fi
  if ! curl "${curl_args[@]}" "$base_url/models" >/dev/null; then
    echo "Error: llama.cpp is not reachable from the container." >&2
    echo "Start llama-server in WSL2 with --host 0.0.0.0 --port 8080, then retry." >&2
    echo "Use --skip-check only if you intentionally want to install the preset while the server is offline." >&2
    exit 1
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
