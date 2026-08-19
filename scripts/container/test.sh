#!/usr/bin/env bash
set -uo pipefail

if command -v fd >/dev/null 2>&1; then
  echo "fd: $(fd --version)"
else
  echo "Note: fd has not yet been acquired. Start Pi once, then rerun tests."
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
log="/evolution/evaluations/test-$stamp.log"
cd /pi
set +e
{ npm run check && ./test.sh; } 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

passed=$(grep -Eo '[0-9]+ passed' "$log" | tail -1 | grep -Eo '[0-9]+' || true)
failed=$(grep -Eo '[0-9]+ failed' "$log" | tail -1 | grep -Eo '[0-9]+' || true)
skipped=$(grep -Eo '[0-9]+ skipped' "$log" | tail -1 | grep -Eo '[0-9]+' || true)

jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg pi_commit "$(git rev-parse HEAD)" \
  --arg branch "$(git branch --show-current)" \
  --arg log "$log" \
  --argjson exit_code "$status" \
  --arg passed "${passed:-unknown}" \
  --arg failed "${failed:-unknown}" \
  --arg skipped "${skipped:-unknown}" \
  '{timestamp:$timestamp,pi_commit:$pi_commit,branch:$branch,exit_code:$exit_code,summary:{passed:$passed,failed:$failed,skipped:$skipped},log:$log}' \
  > "/evolution/evaluations/test-$stamp.json"

echo
echo "Evaluation: passed=${passed:-unknown} failed=${failed:-unknown} skipped=${skipped:-unknown} exit=$status"
echo "Recorded: /evolution/evaluations/test-$stamp.json"
if [[ "$status" -ne 0 ]] && grep -qi microsoft /proc/version; then
  echo "WSL2 note: compare clipboard failures with docs/GENERATION_0.md; two readClipboardImage cases are historical baseline failures."
fi
exit "$status"
