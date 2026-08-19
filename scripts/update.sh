#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

rebase=false
if [[ "${1:-}" == --rebase ]]; then
  rebase=true
  shift
fi
[[ $# -eq 0 ]] || die "Usage: ./scripts/update.sh [--rebase]"

require_initialized
if [[ "$rebase" == true ]]; then
  container_script_run update.sh --rebase
else
  container_script_run update.sh
fi
