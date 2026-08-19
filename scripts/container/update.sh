#!/usr/bin/env bash
set -euo pipefail

cd /pi
git fetch origin

if [[ "${1:-}" == --rebase ]]; then
  [[ -z "$(git status --porcelain)" ]] || {
    echo "Refusing to rebase with uncommitted changes." >&2
    exit 1
  }
  git rebase origin/main
  npm install --ignore-scripts
  npm run build
  npm run check
else
  echo "Current branch: $(git branch --show-current)"
  git status --short --branch
  echo
  echo "Commits available on origin/main:"
  git log --oneline --decorate HEAD..origin/main || true
  echo
  echo "Review these changes, then rerun the update command with its explicit rebase option if desired."
fi
