#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

selected_model=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      shift
      [[ $# -gt 0 ]] || die "--model requires a value."
      selected_model="$1"
      ;;
    -h|--help)
      printf 'Usage: ./setup.sh [--model qwen3.8-27b]\n'
      exit 0
      ;;
    *)
      die "Usage: ./setup.sh [--model qwen3.8-27b]"
      ;;
  esac
  shift
done
[[ -z "$selected_model" || "$selected_model" == qwen3.8-27b ]] || \
  die "Unknown model profile '$selected_model'. Expected qwen3.8-27b."

phase "1/12" "Checking Docker"
require_docker

phase "2/12" "Checking requested model"
if [[ "$selected_model" == qwen3.8-27b ]]; then
  "$REPO_ROOT/scripts/models/qwen3.8-27b/check.sh"
else
  printf 'No explicit model profile requested; continuing with Pi model selection.\n'
fi

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$REPO_ROOT/.env.example" "$ENV_FILE"
  printf 'Created %s from .env.example\n' "$ENV_FILE"
fi

phase "3/12" "Initializing agent evolution repository"
initialize_agent_evolution

phase "4/12" "Building Generation 0 substrate"
docker compose --project-directory "$REPO_ROOT" --file "$REPO_ROOT/compose.yaml" build pi

phase "5/12" "Creating persistent volumes"
for volume in "$SOURCE_VOLUME" "$AGENT_VOLUME" "$EVOLUTION_VOLUME"; do
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume" >/dev/null
done

base_mount_args
docker run --rm --user root --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" "$PI_IMAGE" -lc \
  'mkdir -p /pi /home/pi/.pi-agent/bin /evolution/generations /evolution/observations /evolution/evaluations && chown -R pi:pi /pi /home/pi/.pi-agent /evolution'

phase "6/12" "Initializing persistent Pi source"
docker run --rm --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" \
  --env "PI_GIT_NAME=$PI_GIT_NAME" \
  --env "PI_GIT_EMAIL=$PI_GIT_EMAIL" \
  --volume "$REPO_ROOT/scripts/container:/opt/pi-evolving:ro" \
  "$PI_IMAGE" /opt/pi-evolving/init-source.sh

phase "7/12" "Installing Pi dependencies"
maintenance_run 'cd /pi && npm install --ignore-scripts'

phase "8/12" "Building Pi"
maintenance_run 'cd /pi && npm run build'

phase "9/12" "Running Pi checks"
maintenance_run 'cd /pi && npm run check'

phase "10/12" "Installing evolution policy and recording Generation 0"
docker run --rm --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" \
  --volume "$REPO_ROOT/scripts/container:/opt/pi-evolving:ro" \
  --volume "$REPO_ROOT/config/AGENTS.md:/tmp/pi-evolving-AGENTS.md:ro" \
  --env "PI_HOST_PLATFORM=$(uname -s)" \
  "$PI_IMAGE" /opt/pi-evolving/install-policy.sh

phase "11/12" "Installing agent evolution capabilities"
if [[ -n "$PI_AGENT_EVOLUTION_PATH" ]]; then
  install_agent_evolution_if_configured
else
  printf 'No agent evolution repository configured.\n'
fi

phase "12/12" "Configuring requested model"
if [[ "$selected_model" == qwen3.8-27b ]]; then
  "$REPO_ROOT/scripts/local-model.sh" --profile qwen3.8-27b --smoke-test
else
  printf 'No explicit model profile requested.\n'
fi

printf '\nSetup complete.\n  Run Pi:  ./pi.sh /path/to/project\n  Shell:   ./shell.sh\n  Tests:   ./test.sh\n'
