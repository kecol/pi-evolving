#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

skip_check=0
if [[ "${1:-}" == --skip-check ]]; then
  skip_check=1
  shift
fi
[[ $# -eq 0 ]] || die "Usage: ./scripts/local-model.sh [--skip-check]"

require_initialized
base_mount_args
docker run --rm --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" \
  --volume "$REPO_ROOT/scripts/container:/opt/pi-evolving:ro" \
  --volume "$REPO_ROOT/config/models.llamacpp-wsl.json:/tmp/pi-evolving-models.json:ro" \
  --env "PI_SKIP_LOCAL_MODEL_CHECK=$skip_check" \
  "$PI_IMAGE" /opt/pi-evolving/install-local-model.sh

set_env_value() {
  local key="$1"
  local value="$2"
  local temporary
  temporary=$(mktemp "$REPO_ROOT/.env.XXXXXX")
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    $0 ~ "^" key "=" { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$ENV_FILE" > "$temporary"
  mv "$temporary" "$ENV_FILE"
}

set_env_value PI_PROVIDER llamacpp-wsl
set_env_value PI_MODEL local-coder

printf '\nLocal model preset enabled.\n'
printf 'Run: ./pi.sh /path/to/project\n'
