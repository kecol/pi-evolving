#!/usr/bin/env bash
set -euo pipefail

echo "Current generation: $(cat /evolution/CURRENT 2>/dev/null || echo unknown)"
echo "Pi commit: $(git -C /pi rev-parse --short HEAD)"
echo "Branch: $(git -C /pi branch --show-current)"
echo
echo "Git status"
git -C /pi status --short --branch
echo
echo "Recent lineage"
git -C /pi log --graph --decorate --oneline --all -30
echo
echo "Generation records"
for record in /evolution/generations/generation-*.json; do
  [[ -e "$record" ]] || continue
  jq -r '"generation \(.generation): \(.timestamp)  \(.pi_commit[0:12])  \(.branch)"' "$record"
done
