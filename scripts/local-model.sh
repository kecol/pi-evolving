#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

skip_check=0
smoke_test=0
profile=llamacpp-wsl
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-check)
      skip_check=1
      ;;
    --smoke-test)
      smoke_test=1
      ;;
    --profile)
      shift
      [[ $# -gt 0 ]] || die "--profile requires a value."
      profile="$1"
      ;;
    *)
      die "Usage: ./scripts/local-model.sh [--profile llamacpp-wsl|qwen3.8-27b] [--skip-check] [--smoke-test]"
      ;;
  esac
  shift
done
[[ "$skip_check" == 0 || "$smoke_test" == 0 ]] || \
  die "--skip-check and --smoke-test cannot be used together."

case "$profile" in
  llamacpp-wsl)
    model_template="$REPO_ROOT/config/models.llamacpp-wsl.json"
    ;;
  qwen3.8-27b)
    model_template="$REPO_ROOT/models/qwen3.8-27b/models.json"
    ;;
  *)
    die "Unknown local model profile '$profile'. Expected llamacpp-wsl or qwen3.8-27b."
    ;;
esac

require_initialized
base_mount_args
docker run --rm --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" \
  --volume "$REPO_ROOT/scripts/container:/opt/pi-evolving:ro" \
  --volume "$model_template:/tmp/pi-evolving-models.json:ro" \
  --env "PI_SKIP_LOCAL_MODEL_CHECK=$skip_check" \
  --env "PI_LOCAL_MODEL_SMOKE_TEST=$smoke_test" \
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

printf '\nLocal model profile enabled: %s\n' "$profile"
printf 'Run: ./pi.sh /path/to/project\n'
