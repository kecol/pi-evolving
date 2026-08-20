#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ -n "$PI_AGENT_EVOLUTION_PATH" ]] || \
  die "Set PI_AGENT_EVOLUTION_PATH in .env to your agent-evolution repository."
require_initialized
if [[ $# -eq 0 ]]; then
  set -- status
fi
container_script_run agent-evolution.sh "$@"
