#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage="Usage: ./pi.sh <workspace> [--read-only-mount <host-path> <container-path>]... [--] [Pi arguments...]"
[[ $# -ge 1 ]] || die "$usage"
workspace_input="$1"
shift
[[ -d "$workspace_input" ]] || die "Workspace directory does not exist: $workspace_input"
workspace="$(realpath "$workspace_input")"

readonly_mount_args=()
declare -A readonly_targets=()

add_readonly_mount() {
  local host_input="$1" container_path="$2" host_path
  [[ -d "$host_input" ]] || die "Read-only host directory does not exist: $host_input"
  [[ "$container_path" == /* && "$container_path" != //* && "$container_path" != *:* && \
     "$container_path" != *\\* && \
     "/$container_path/" != *"/../"* && \
     "/$container_path/" != *"/./"* ]] || \
    die "Read-only container path must be an absolute normalized Linux path: $container_path"
  container_path="${container_path%/}"
  [[ -n "$container_path" ]] || container_path="/"
  case "$container_path/" in
    //|/pi/*|/agent/*|/workspace/*|/evolution/*|/home/pi/*)
      die "Read-only container path overlaps a managed Pi location: $container_path"
      ;;
  esac
  [[ -z "${readonly_targets[$container_path]:-}" ]] || \
    die "Duplicate read-only container path: $container_path"
  host_path="$(realpath "$host_input")"
  readonly_targets[$container_path]=1
  readonly_mount_args+=(--volume "$host_path:$container_path:ro")
}

if [[ -n "$PI_READONLY_HOST_PATH" || -n "$PI_READONLY_CONTAINER_PATH" ]]; then
  [[ -n "$PI_READONLY_HOST_PATH" && -n "$PI_READONLY_CONTAINER_PATH" ]] || \
    die "PI_READONLY_HOST_PATH and PI_READONLY_CONTAINER_PATH must be configured together."
  readonly_env_host="$PI_READONLY_HOST_PATH"
  if [[ "$readonly_env_host" != /* ]]; then
    readonly_env_host="$REPO_ROOT/$readonly_env_host"
  fi
  add_readonly_mount "$readonly_env_host" "$PI_READONLY_CONTAINER_PATH"
fi

forwarded_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --read-only-mount)
      [[ $# -ge 3 ]] || die "$usage"
      add_readonly_mount "$2" "$3"
      shift 3
      ;;
    --)
      shift
      forwarded_args+=("$@")
      break
      ;;
    *)
      forwarded_args+=("$1")
      shift
      ;;
  esac
done

require_initialized
install_agent_evolution_if_configured
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
  "${readonly_mount_args[@]}" \
  --publish "127.0.0.1:$PI_HOST_PORT:$PI_CONTAINER_PORT" \
  --env PI_SKIP_VERSION_CHECK=1 \
  "$PI_IMAGE" \
  "${pi_args[@]}" "${forwarded_args[@]}"
