#!/usr/bin/env bash
set -euo pipefail

policy=/home/pi/.pi-agent/AGENTS.md
if [[ -f "$policy" ]] && ! cmp -s "$policy" /tmp/pi-evolving-AGENTS.md; then
  backup="/home/pi/.pi-agent/AGENTS.backup.$(date -u +%Y%m%dT%H%M%SZ).md"
  cp "$policy" "$backup"
  echo "Preserved customized global policy at $backup"
fi
cp /tmp/pi-evolving-AGENTS.md "$policy"

record=/evolution/generations/generation-0000.json
if [[ ! -f "$record" ]]; then
  commit=$(git -C /pi rev-parse HEAD)
  branch=$(git -C /pi branch --show-current)
  version=$(node -p 'require("/pi/packages/coding-agent/package.json").version' 2>/dev/null || echo unknown)
  fd_version=$(fd --version 2>/dev/null || echo "not yet acquired")
  jq -n \
    --argjson generation 0 \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg pi_commit "$commit" \
    --arg pi_version "$version" \
    --arg branch "$branch" \
    --arg host_platform "$PI_HOST_PLATFORM" \
    --arg kernel "$(uname -r)" \
    --arg node_version "$(node --version)" \
    --arg npm_version "$(npm --version)" \
    --arg uv_version "$(uv --version)" \
    --arg fd_version "$fd_version" \
    '{generation:$generation,timestamp:$timestamp,pi_commit:$pi_commit,pi_version:$pi_version,branch:$branch,host_platform:$host_platform,kernel:$kernel,node_version:$node_version,npm_version:$npm_version,uv_version:$uv_version,fd_version:$fd_version,test_summary:{passed:null,failed:null,skipped:null},known_failures:[]}' \
    > "$record"
  echo 0 > /evolution/CURRENT
fi
