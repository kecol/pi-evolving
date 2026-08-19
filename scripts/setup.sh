#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

phase "1/8" "Checking Docker"
require_docker

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$REPO_ROOT/.env.example" "$ENV_FILE"
  printf 'Created %s from .env.example\n' "$ENV_FILE"
fi

phase "2/8" "Building Generation 0 substrate"
docker compose --project-directory "$REPO_ROOT" --file "$REPO_ROOT/compose.yaml" build pi

phase "3/8" "Creating persistent volumes"
for volume in "$SOURCE_VOLUME" "$AGENT_VOLUME" "$EVOLUTION_VOLUME"; do
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume" >/dev/null
done

base_mount_args
docker run --rm --user root --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" "$PI_IMAGE" -lc \
  'mkdir -p /pi /home/pi/.pi-agent/bin /evolution/generations /evolution/observations /evolution/evaluations && chown -R pi:pi /pi /home/pi/.pi-agent /evolution'

phase "4/8" "Initializing persistent Pi source"
docker run --rm --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" \
  --env "PI_GIT_NAME=$PI_GIT_NAME" \
  --env "PI_GIT_EMAIL=$PI_GIT_EMAIL" \
  --volume "$REPO_ROOT/scripts/container:/opt/pi-evolving:ro" \
  "$PI_IMAGE" /opt/pi-evolving/init-source.sh

phase "5/8" "Installing Pi dependencies"
maintenance_run 'cd /pi && npm install --ignore-scripts'

phase "6/8" "Building Pi"
maintenance_run 'cd /pi && npm run build'

phase "7/8" "Running Pi checks"
maintenance_run 'cd /pi && npm run check'

phase "8/8" "Installing evolution policy and recording Generation 0"
docker run --rm --entrypoint bash \
  "${BASE_MOUNT_ARGS[@]}" \
  --volume "$REPO_ROOT/scripts/container:/opt/pi-evolving:ro" \
  --volume "$REPO_ROOT/config/AGENTS.md:/tmp/pi-evolving-AGENTS.md:ro" \
  --env "PI_HOST_PLATFORM=$(uname -s)" \
  "$PI_IMAGE" /opt/pi-evolving/install-policy.sh

printf '\nSetup complete.\n  Run Pi:  ./pi.sh /path/to/project\n  Shell:   ./shell.sh\n  Tests:   ./test.sh\n'
