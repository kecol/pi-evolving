#!/usr/bin/env bash

set -euo pipefail

AGENT_REPO="${PI_AGENT_EVOLUTION_ROOT:-/agent}"
RUNTIME_ROOT="${PI_AGENT_RUNTIME_ROOT:-/home/pi/.pi-agent}"
MANIFEST="$AGENT_REPO/agent.json"
LOCK="$RUNTIME_ROOT/agent.lock.json"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

sha256() {
  sha256sum "$1" | cut -d' ' -f1
}

validate_repo() {
  [[ -d "$AGENT_REPO/.git" ]] || die "$AGENT_REPO is not a Git repository."
  [[ -f "$MANIFEST" ]] || die "Missing agent evolution manifest: $MANIFEST"
  jq -e '
    .schemaVersion == 1 and
    (.capabilities | type == "array") and
    all(.capabilities[];
      (.type | type == "string") and
      (.source | type == "string") and
      (.target | type == "string")
    )
  ' "$MANIFEST" >/dev/null || die "Invalid agent.json (expected schemaVersion 1 and a capabilities array)."
}

validate_relative_path() {
  local path="$1"
  [[ -n "$path" && "$path" != /* && "$path" != *\\* && \
     "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]] || return 1
  [[ "/$path/" != *"/../"* && "/$path/" != *"/./"* && "$path" != */ ]] || return 1
}

validate_capability() {
  local type="$1" source="$2" target="$3" expected_prefix source_real target_real
  validate_relative_path "$source" || die "Unsafe capability source path: $source"
  validate_relative_path "$target" || die "Unsafe capability target path: $target"
  case "$type" in
    extension) expected_prefix="extensions/" ;;
    skill) expected_prefix="skills/" ;;
    prompt) expected_prefix="prompts/" ;;
    *) die "Unsupported capability type '$type'. Expected extension, skill, or prompt." ;;
  esac
  [[ "$source" == "$expected_prefix"* && "$target" == "$expected_prefix"* ]] || \
    die "Capability '$source' must remain under $expected_prefix in source and target."
  [[ -f "$AGENT_REPO/$source" && ! -L "$AGENT_REPO/$source" ]] || \
    die "Capability source must be a regular file, not a symlink: $source"
  source_real="$(realpath -e "$AGENT_REPO/$source")"
  target_real="$(realpath -m "$RUNTIME_ROOT/$target")"
  [[ "$source_real" == "$(realpath -e "$AGENT_REPO")/"* ]] || \
    die "Capability source resolves outside /agent: $source"
  [[ "$target_real" == "$(realpath -m "$RUNTIME_ROOT")/"* ]] || \
    die "Capability target resolves outside .pi-agent: $target"
}

repo_dirty() {
  [[ -n "$(git -C "$AGENT_REPO" status --porcelain --untracked-files=normal)" ]]
}

manifest_rows() {
  jq -r '.capabilities[] | [.type, .source, .target] | @tsv' "$MANIFEST"
}

lock_hash_for() {
  local target="$1"
  [[ -f "$LOCK" ]] || return 0
  jq -r --arg target "$target" '.capabilities[]? | select(.target == $target) | .sha256' "$LOCK" | head -n 1
}

check_target_safety() {
  local source="$1" target="$2" destination="$RUNTIME_ROOT/$2"
  local source_hash current_hash locked_hash
  source_hash="$(sha256 "$AGENT_REPO/$source")"
  [[ ! -L "$destination" ]] || die "Refusing to replace runtime symlink: $target"
  [[ -e "$destination" ]] || return 0
  [[ -f "$destination" ]] || die "Runtime target is not a regular file: $target"
  current_hash="$(sha256 "$destination")"
  locked_hash="$(lock_hash_for "$target")"
  if [[ -z "$locked_hash" && "$current_hash" != "$source_hash" ]]; then
    die "Runtime target already exists and is unmanaged: $target (move it aside or make it match the repository copy)."
  fi
  if [[ -n "$locked_hash" && "$current_hash" != "$locked_hash" && "$current_hash" != "$source_hash" ]]; then
    die "Runtime drift detected at $target; refusing to overwrite local changes."
  fi
}

install_capability() {
  local source="$1" target="$2" destination="$RUNTIME_ROOT/$2" temp
  mkdir -p "$(dirname "$destination")"
  temp="$(mktemp "$(dirname "$destination")/.agent-install.XXXXXX")"
  install -m 0644 "$AGENT_REPO/$source" "$temp"
  mv -f "$temp" "$destination"
}

write_lock() {
  local commit="$1" working_tree="$2" records="$3" temp
  temp="$(mktemp "$RUNTIME_ROOT/.agent-lock.XXXXXX")"
  jq -s \
    --arg commit "$commit" \
    --argjson workingTree "$working_tree" \
    '{schemaVersion: 1, commit: $commit, workingTree: $workingTree,
      installedAt: (now | todateiso8601), capabilities: .}' \
    "$records" > "$temp"
  mv -f "$temp" "$LOCK"
}

install_agent() {
  local allow_working_tree=false commit records type source target desired_json
  local runtime_current=true
  local -a rows=()
  local -A targets=()
  if [[ "${1:-}" == "--working-tree" ]]; then
    allow_working_tree=true
    shift
  fi
  [[ $# -eq 0 ]] || die "Usage: pi-agent-evolution install [--working-tree]"
  validate_repo
  commit="$(git -C "$AGENT_REPO" rev-parse --verify HEAD 2>/dev/null)" || \
    die "The agent evolution repository has no commit yet."
  if repo_dirty && [[ "$allow_working_tree" != true ]]; then
    die "The agent evolution repository is dirty. Commit changes or use install --working-tree explicitly."
  fi

  records="$(mktemp)"
  trap 'rm -f "$records"' RETURN
  mapfile -t rows < <(manifest_rows)
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r type source target <<< "$row"
    validate_capability "$type" "$source" "$target"
    [[ -z "${targets[$target]:-}" ]] || die "Duplicate capability target: $target"
    targets[$target]=1
    check_target_safety "$source" "$target"
    if [[ ! -f "$RUNTIME_ROOT/$target" ]] || \
       [[ "$(sha256 "$AGENT_REPO/$source")" != "$(sha256 "$RUNTIME_ROOT/$target")" ]]; then
      runtime_current=false
    fi
    jq -n --arg type "$type" --arg source "$source" --arg target "$target" \
      --arg sha256 "$(sha256 "$AGENT_REPO/$source")" \
      '{type: $type, source: $source, target: $target, sha256: $sha256}' >> "$records"
  done

  desired_json="$(jq -s . "$records")"
  if [[ "$allow_working_tree" == false && "$runtime_current" == true && -f "$LOCK" ]] && \
     jq -e --arg commit "$commit" --argjson capabilities "$desired_json" \
       '.commit == $commit and .workingTree == false and .capabilities == $capabilities' \
       "$LOCK" >/dev/null; then
    rm -f "$records"
    trap - RETURN
    printf 'Agent evolution is already current at %s.\n' "$commit"
    return 0
  fi

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r _type source target <<< "$row"
    if [[ ! -f "$RUNTIME_ROOT/$target" ]] || \
       [[ "$(sha256 "$AGENT_REPO/$source")" != "$(sha256 "$RUNTIME_ROOT/$target")" ]]; then
      install_capability "$source" "$target"
      printf 'Installed %s\n' "$target"
    fi
  done
  write_lock "$commit" "$allow_working_tree" "$records"
  rm -f "$records"
  trap - RETURN
  printf 'Agent evolution installed at %s%s.\n' "$commit" \
    "$([[ "$allow_working_tree" == true ]] && printf ' (working tree snapshot)')"
}

status_agent() {
  local commit dirty=false type source target source_hash current_hash locked_hash state
  validate_repo
  commit="$(git -C "$AGENT_REPO" rev-parse --short HEAD 2>/dev/null || printf '(no commit)')"
  repo_dirty && dirty=true
  printf 'Repository: %s (dirty: %s)\n' "$commit" "$dirty"
  if [[ -f "$LOCK" ]]; then
    printf 'Installed:  %s (working tree: %s)\n' \
      "$(jq -r '.commit' "$LOCK")" "$(jq -r '.workingTree' "$LOCK")"
  else
    printf 'Installed:  none\n'
  fi
  while IFS=$'\t' read -r type source target; do
    validate_capability "$type" "$source" "$target"
    source_hash="$(sha256 "$AGENT_REPO/$source")"
    locked_hash="$(lock_hash_for "$target")"
    if [[ ! -e "$RUNTIME_ROOT/$target" ]]; then
      state=missing
    elif [[ -L "$RUNTIME_ROOT/$target" || ! -f "$RUNTIME_ROOT/$target" ]]; then
      state=unsafe
    else
      current_hash="$(sha256 "$RUNTIME_ROOT/$target")"
      if [[ "$current_hash" == "$source_hash" ]]; then
        state=current
      elif [[ -n "$locked_hash" && "$current_hash" == "$locked_hash" ]]; then
        state=update-available
      else
        state=drift
      fi
    fi
    printf '%-16s %s\n' "$state" "$target"
  done < <(manifest_rows)
}

history_agent() {
  [[ -d "$AGENT_REPO/.git" ]] || die "$AGENT_REPO is not a Git repository."
  git -C "$AGENT_REPO" log --oneline --decorate --graph "${@:---all}"
}

case "${1:-status}" in
  install) shift; install_agent "$@" ;;
  status) shift; [[ $# -eq 0 ]] || die "Usage: pi-agent-evolution status"; status_agent ;;
  history) shift; history_agent "$@" ;;
  *) die "Usage: pi-agent-evolution {status|install [--working-tree]|history}" ;;
esac
