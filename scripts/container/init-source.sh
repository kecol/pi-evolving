#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d /pi/.git ]]; then
  if [[ -n "$(find /pi -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Error: /pi contains files but is not a Git checkout; refusing to overwrite it." >&2
    exit 1
  fi
  git clone https://github.com/earendil-works/pi.git /pi
else
  echo "Existing Pi checkout found; preserving it."
fi

cd /pi
git config --local user.name >/dev/null 2>&1 || git config --local user.name "$PI_GIT_NAME"
git config --local user.email >/dev/null 2>&1 || git config --local user.email "$PI_GIT_EMAIL"

if ! git show-ref --verify --quiet refs/heads/evolve; then
  git switch -c evolve
elif [[ "$(git branch --show-current)" != evolve ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Preserving current branch and uncommitted changes; switch to evolve manually when ready."
  else
    git switch evolve
  fi
fi
