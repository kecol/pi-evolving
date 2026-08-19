#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ $# -ge 1 ]] || die "Usage: ./pi.sh <workspace> [Pi arguments...]"
workspace_input="$1"
shift
[[ -d "$workspace_input" ]] || die "Workspace directory does not exist: $workspace_input"
workspace="$(realpath "$workspace_input")"

require_initialized
base_mount_args
pi_args=()
if [[ -n "$PI_PROVIDER" ]]; then
  pi_args+=(--provider "$PI_PROVIDER")
fi
if [[ -n "$PI_MODEL" ]]; then
  pi_args+=(--model "$PI_MODEL")
fi

docker run --rm -it \
  --name "$CONTAINER_NAME" \
  "${BASE_MOUNT_ARGS[@]}" \
  --volume "$workspace:/workspace" \
  --publish "127.0.0.1:$PI_HOST_PORT:$PI_CONTAINER_PORT" \
  --env PI_SKIP_VERSION_CHECK=1 \
  "$PI_IMAGE" \
  "${pi_args[@]}" "$@"
