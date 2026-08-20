#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [[ -f "$ENV_FILE" ]]; then
  # Parse simple KEY=value lines without executing the user-owned file.
  while IFS='=' read -r key value || [[ -n "${key:-}" ]]; do
    key="${key%$'\r'}"
    value="${value%$'\r'}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    printf -v "$key" '%s' "$value"
    export "$key"
  done < "$ENV_FILE"
fi

PI_IMAGE="${PI_IMAGE:-pi-evolving:local}"
PI_PROVIDER="${PI_PROVIDER:-}"
PI_MODEL="${PI_MODEL:-}"
PI_HOST_PORT="${PI_HOST_PORT:-9191}"
PI_CONTAINER_PORT="${PI_CONTAINER_PORT:-9191}"
PI_GIT_NAME="${PI_GIT_NAME:-Pi Evolving Agent}"
PI_GIT_EMAIL="${PI_GIT_EMAIL:-pi-evolving@local}"
PI_AGENT_EVOLUTION_PATH="${PI_AGENT_EVOLUTION_PATH:-}"
PI_AGENT_AUTO_INSTALL="${PI_AGENT_AUTO_INSTALL:-1}"

SOURCE_VOLUME="pi-evolving-source"
AGENT_VOLUME="pi-evolving-agent-state"
EVOLUTION_VOLUME="pi-evolving-evolution-state"
CONTAINER_NAME="pi-evolving"

phase() {
  printf '\n[%s] %s\n' "$1" "$2"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed or is not on PATH."
  docker version >/dev/null 2>&1 || die "Docker is installed, but its daemon is unavailable."
}

require_initialized() {
  require_docker
  docker image inspect "$PI_IMAGE" >/dev/null 2>&1 || \
    die "Image '$PI_IMAGE' is missing. Run ./setup.sh first."
  docker volume inspect "$SOURCE_VOLUME" >/dev/null 2>&1 || \
    die "Pi source volume is missing. Run ./setup.sh first."
}

base_mount_args() {
  BASE_MOUNT_ARGS=(
    --add-host "host.docker.internal:host-gateway"
    --volume "$SOURCE_VOLUME:/pi"
    --volume "$AGENT_VOLUME:/home/pi/.pi-agent"
    --volume "$EVOLUTION_VOLUME:/evolution"
  )
  if [[ -n "$PI_AGENT_EVOLUTION_PATH" ]]; then
    [[ "$PI_AGENT_EVOLUTION_PATH" == /* ]] || \
      die "PI_AGENT_EVOLUTION_PATH must be an absolute path."
    [[ -d "$PI_AGENT_EVOLUTION_PATH" ]] || \
      die "Agent evolution directory does not exist: $PI_AGENT_EVOLUTION_PATH"
    BASE_MOUNT_ARGS+=(--volume "$(realpath "$PI_AGENT_EVOLUTION_PATH"):/agent")
  fi
}

maintenance_run() {
  base_mount_args
  docker run --rm \
    --entrypoint bash \
    "${BASE_MOUNT_ARGS[@]}" \
    "$PI_IMAGE" -lc "$1"
}

container_script_run() {
  local script_name="$1"
  shift
  base_mount_args
  docker run --rm \
    --entrypoint bash \
    "${BASE_MOUNT_ARGS[@]}" \
    --volume "$REPO_ROOT/scripts/container:/opt/pi-evolving:ro" \
    "$PI_IMAGE" "/opt/pi-evolving/$script_name" "$@"
}

install_agent_evolution_if_configured() {
  [[ -n "$PI_AGENT_EVOLUTION_PATH" ]] || return 0
  case "$PI_AGENT_AUTO_INSTALL" in
    1|true|TRUE|yes|YES) container_script_run agent-evolution.sh install ;;
    0|false|FALSE|no|NO) printf 'Agent evolution auto-install is disabled.\n' ;;
    *) die "PI_AGENT_AUTO_INSTALL must be 1 or 0 (also accepts true/false or yes/no)." ;;
  esac
}
