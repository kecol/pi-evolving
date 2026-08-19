#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

target="${1:-}"
case "$target" in
  agent-state) volumes=("$AGENT_VOLUME") ;;
  source) volumes=("$SOURCE_VOLUME") ;;
  evolution) volumes=("$EVOLUTION_VOLUME") ;;
  all) volumes=("$SOURCE_VOLUME" "$AGENT_VOLUME" "$EVOLUTION_VOLUME") ;;
  *) die "Usage: ./scripts/reset.sh {agent-state|source|evolution|all}" ;;
esac

require_docker
printf 'This will permanently delete %s persistent data. The workspace will not be touched.\n' "$target"
read -r -p "Type '$target' to confirm: " confirmation
[[ "$confirmation" == "$target" ]] || die "Reset cancelled."

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  die "Container '$CONTAINER_NAME' exists. Stop it before resetting state."
fi
for volume in "${volumes[@]}"; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker volume rm "$volume"
  fi
done
printf 'Reset complete. Run ./setup.sh to recreate required state.\n'
