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
if [[ -v PI_AGENT_EVOLUTION_PATH ]]; then
  PI_AGENT_EVOLUTION_PATH_RAW="$PI_AGENT_EVOLUTION_PATH"
else
  PI_AGENT_EVOLUTION_PATH_RAW="../pi-agent-evolution"
fi
if [[ -n "$PI_AGENT_EVOLUTION_PATH_RAW" ]]; then
  if [[ "$PI_AGENT_EVOLUTION_PATH_RAW" == /* ]]; then
    PI_AGENT_EVOLUTION_PATH="$(realpath -m "$PI_AGENT_EVOLUTION_PATH_RAW")"
  else
    PI_AGENT_EVOLUTION_PATH="$(realpath -m "$REPO_ROOT/$PI_AGENT_EVOLUTION_PATH_RAW")"
  fi
else
  PI_AGENT_EVOLUTION_PATH=""
fi
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
    [[ -d "$PI_AGENT_EVOLUTION_PATH" ]] || \
      die "Agent evolution directory does not exist: $PI_AGENT_EVOLUTION_PATH (run ./setup.sh)."
    BASE_MOUNT_ARGS+=(--volume "$PI_AGENT_EVOLUTION_PATH:/agent")
  fi
}

initialize_agent_evolution() {
  local path="$PI_AGENT_EVOLUTION_PATH" template_root="$REPO_ROOT/config/agent-repository"
  local git_root="" repository_initialized=false
  [[ -n "$path" ]] || {
    printf 'Agent evolution is disabled by an empty PI_AGENT_EVOLUTION_PATH.\n'
    return 0
  }
  command -v git >/dev/null 2>&1 || die "Git is required to initialize $path."

  if [[ -e "$path" && ! -d "$path" ]]; then
    die "Agent evolution path exists but is not a directory: $path"
  fi
  if [[ -d "$path" ]]; then
    git_root="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  if [[ -n "$git_root" && "$(realpath -m "$git_root")" == "$path" ]]; then
    if [[ -f "$path/agent.json" ]]; then
      printf 'Using existing agent evolution repository: %s\n' "$path"
      if [[ ! -f "$path/AGENTS.md" ]]; then
        printf 'Note: add %s/AGENTS.md to give Pi repository-specific capability instructions.\n' "$path"
      fi
      return 0
    fi
    if [[ -n "$(find "$path" -mindepth 1 -maxdepth 1 ! -name .git -print -quit)" ]]; then
      die "Existing agent evolution repository is missing agent.json: $path"
    fi
    repository_initialized=true
  fi
  if [[ "$repository_initialized" == false && -d "$path" && \
        -n "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    die "Refusing to initialize non-empty, non-Git directory: $path"
  fi

  mkdir -p "$path/extensions" "$path/skills" "$path/prompts"
  cp "$template_root/AGENTS.md" "$path/AGENTS.md"
  cp "$template_root/README.md" "$path/README.md"
  cp "$template_root/agent.json" "$path/agent.json"
  : > "$path/extensions/.gitkeep"
  : > "$path/skills/.gitkeep"
  : > "$path/prompts/.gitkeep"
  if [[ "$repository_initialized" == false ]]; then
    git -C "$path" init -b main >/dev/null
  fi
  git -C "$path" config user.name "$PI_GIT_NAME"
  git -C "$path" config user.email "$PI_GIT_EMAIL"
  git -C "$path" add AGENTS.md README.md agent.json extensions/.gitkeep skills/.gitkeep prompts/.gitkeep
  git -C "$path" commit -m "capability: initialize agent evolution repository" >/dev/null
  printf 'Created agent evolution repository: %s\n' "$path"
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
