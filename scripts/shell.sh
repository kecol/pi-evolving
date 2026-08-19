#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_initialized
if [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" == true ]]; then
  exec docker exec -it "$CONTAINER_NAME" bash
fi

base_mount_args
exec docker run --rm -it --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" "$PI_IMAGE"
